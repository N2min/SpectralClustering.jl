using NearestNeighbors
using StatsBase
using Statistics
export VertexNeighborhood,
       KNNNeighborhood,
       create,
       PixelNeighborhood,
       local_scale,
       neighbors,
       RandomNeighborhood,
       CliqueNeighborhood


import SpectralClustering: spatial_position
import Base.ones
"""
```julia
struct RandomKGraph
```
The type RandomKGraph defines the parameters needed to create a random k-graph.
Every vertex it is connected to `k` random neigbors.
# Members
- `number_of_vertices::Integer`. Defines the number of vertices of the graph.
- `k::Integer`. Defines the minimum number of  neighborhood of every vertex.
"""
struct RandomKGraph
    number_of_vertices::Integer
    k::Integer
end
"""
```julia
create(cfg::RandomKGraph)
```
Construct a [`RandomKGraph`](@ref) such that every vertex is connected with other k random vertices.
"""
function create(cfg::RandomKGraph)
    g = Graph(cfg.number_of_vertices)
    for i = 1:cfg.number_of_vertices
        cant = 0
        while cant < cfg.k
            selected = rand(1:cfg.number_of_vertices)
            while selected == i
                selected = rand(1:cfg.number_of_vertices)
            end
            connect!(g, i, selected, rand())
            cant = cant + 1
        end
    end
    return g;
end
"""
```julia
abstract type VertexNeighborhood end
```
The abstract type VertexNeighborhood provides an interface to query for the
neighborhood of a given vertex. Every concrete type that inherit from
VertexNeighborhood must define the function
```julia
neighbors{T<:VertexNeighborhood}(cfg::T, j::Integer, data)
```
which returns the neighbors list of the vertex j for the given data.
"""
abstract type VertexNeighborhood end
"""
```julia
struct PixelNeighborhood  <: VertexNeighborhood
```
`PixelNeighborhood` defines neighborhood for a given pixel based in its spatial location. Given a pixel located at (x,y), returns every pixel inside
\$(x+e,y), (x-e,y)\$ and \$(x,y+e)(x,y-e)\$.

# Members
- e:: Integer. Defines the radius of the neighborhood.

"""
struct PixelNeighborhood  <: VertexNeighborhood
    e::Integer
end
"""
```julia
neighbors(cfg::PixelNeighborhood, j::Integer, img)
```

Returns the neighbors of the pixel j according to the specified in [`PixelNeighborhood`](@ref)
"""
function neighbors(cfg::PixelNeighborhood, j::Integer, img::Matrix{T}) where T <: Colorant
    pos = CartesianIndices(img)[j]
    w_r = max(pos[1] - cfg.e, 1):min(pos[1] + cfg.e, size(img, 1))
    w_c = max(pos[2] - cfg.e, 1):min(pos[2] + cfg.e, size(img, 2))
    return vec(map(x->LinearIndices(img)[x[1],x[2]], CartesianIndices((w_r, w_c))))
end

"""
```julia
struct CliqueNeighborhood <: VertexNeighborhood
```
`CliqueNeighborhood` specifies that the neighborhood for a given vertex \$j\$ in a
graph of \$n\$ vertices are the remaining n-1 vertices.
"""
struct CliqueNeighborhood <: VertexNeighborhood
end
"""
```julia
neighbors(config::CliqueNeighborhood, j::Integer, X)
```
Return every other vertex index different from \$j\$. See [`CliqueNeighborhood`](@ref)
"""
function neighbors(config::CliqueNeighborhood, j::Integer, X)
  return filter!(x->x != j, collect(1:number_of_patterns(X)))
end
"""
```julia
struct KNNNeighborhood <: VertexNeighborhood
    k::Integer
    tree::KDTree
end
```
`KNNNeighborhood` specifies that the neighborhood for a given vertex \$j\$ are the \$k\$ nearest neighborgs. It uses a tree to search the nearest patterns.
# Members
- `k::Integer`. The number of k nearest neighborgs to connect.
- `tree::KDTree`. Internal data structure.
- `f::Function`. Transformation function
"""
struct KNNNeighborhood <: VertexNeighborhood
  k::Integer
  tree::KDTree
  t::Function
end
"""
```julia
KNNNeighborhood(X::Matrix, k::Integer)
```
Create the [`KNNNeighborhood`](@ref) type by building a `k`-nn tre from de data `X`

Return the indexes of the `config.k` nearest neigbors of the data point `j` of the data `X`.
"""
function KNNNeighborhood(X, k::Integer, f::Function = x->x)
   tree = KDTree(hcat([f(get_element(X, j)) for j = 1:number_of_patterns(X)]...))
    return KNNNeighborhood(k, tree, f)
end
neighbors(config::KNNNeighborhood, j::Integer, X) = neighbors(config, get_element(X, j))
function neighbors(config::KNNNeighborhood, data)
    idxs, dists = knn(config.tree, config.t(data), config.k + 1, true)
    return idxs[2:config.k + 1]
end
"""
```@julia
struct RandomNeighborhood <: VertexNeighborhood
    k::Integer
end
```
For a given index `j`return `k` random vertices different from `j`
"""
struct RandomNeighborhood <: VertexNeighborhood
    k::Integer
end
function neighbors(config::RandomNeighborhood, j::Integer, X)
   samples = StatsBase.sample(1:number_of_patterns(X), config.k, replace = false)
    if (in(j, samples))
        filter!(e->e != j, samples)
    end
    while (length(samples) < config.k)
       s  =  StatsBase.sample(1:number_of_patterns(X), 1)[1]
        if (s != j)
            push!(samples, s)
        end
    end
    return samples
end
"""
```julia
weight{T<:DataAccessor}(w::Function,d::T, i::Int,j::Int,X)
```
Invoke the weight function provided to compute the similarity between the pattern `i` and the pattern `j`.
"""
function weight(w::Function, i::Integer, j::Integer, X)
  x_i = get_element(X, i)
  x_j = get_element(X, j)
  return w(i, j, x_i, x_j)
end

"""
```julia
create(w_type::DataType, neighborhood::VertexNeighborhood, oracle::Function,X)
```
Given a [`VertexNeighborhood`](@ref), a simmilarity function `oracle`  construct a simmilarity graph of the patterns in `X`.
"""
function create(w_type::DataType, neighborhood::VertexNeighborhood, oracle::Function, X)
    number_of_vertices = number_of_patterns(X)
    g = Graph(number_of_vertices; weight_type = w_type)
    @Threads.threads for j = 1:number_of_vertices
        neigh = neighbors(neighborhood, j, X)
        x_j = get_element(X, j)
        x_neigh = get_element(X, neigh)
        weights = oracle(j, neigh, x_j, x_neigh)
        connect!(g, j, neigh, weights)
    end
    GC.gc()
    return g
end
"""
```julia
create(neighborhood::VertexNeighborhood, oracle::Function,X)
```
Given a [`VertexNeighborhood`](@ref), a simmilarity function `oracle` construct a simmilarity graph of the patterns in `X`.
"""
function create(neighborhood::VertexNeighborhood, oracle::Function, X)
    create(Float64, neighborhood, oracle, X)
end
"""
```julia
local_scale(neighborhood::KNNNeighborhood, oracle::Function, X; k::Integer = 7)
```
Computes thescale of each pattern according to [Self-Tuning Spectral Clustering](https://papers.nips.cc/paper/2619-self-tuning-spectral-clustering.pdf).
Return a matrix containing for every pattern the local_scale.

# Arguments
    - `neighborhood::KNNNeighborhood`
    - `oracle::Function`
    - `X`
      the data

\"The selection of thescale \$ \\sigma \$ can be done by studying thestatistics of the neighborhoods surrounding points \$ i \$ and \$ j \$ .i \"
Zelnik-Manor and Perona use \$ \\sigma_i = d(s_i, s_K) \$ where \$s_K\$ is the \$ K \$ neighbor of point \$ s_i \$ .
They \"used a single value of \$K=7\$, which gave good results even for high-dimensional data \" .

"""
function local_scale(neighborhood::T, oracle::Function, X; k::Integer = 7, sortdim::Integer=1) where T<:VertexNeighborhood
    sort_data(d::AbstractArray; dims=1) = sort(d)
    sort_data(d::AbstractMatrix; dims=1) = sort(d, dims=dims)
    temp = nothing
    distance_function = nothing
    try
        temp = oracle(get_element(X, 1), get_element(X, [1, 2]))
        distance_function = (a,b,c,d)->oracle(c, d)
    catch e
        temp = oracle(0, [0], get_element(X, 1), get_element(X, [1, 2]))
        distance_function = oracle
    end
    number_of_vertices = number_of_patterns(X)

    scales = zeros(size(temp, 2), number_of_vertices)
    for j = 1:number_of_vertices
        neigh = neighbors(neighborhood, j, X)
        distances = distance_function(j, neigh, get_element(X, j), get_element(X, neigh))

        scales[:, j] .= sort_data(distances, dims=sortdim)[k, :]
    end
    return scales
end


#="""
Given a graph (g) created from a X_prev \in R^{d x n}, updates de graph from
the matrix X \in R^{d x m}, m > n. Adding the correspondent vertices and connecting
them whith the existing ones.
"""
function update!(config::GraphCreationConfig,g::Graph,X)
  number_of_vertices = number_of_patterns(config.da,X)
  old_number_of_vertices = number_of_vertices(g)
  for j=old_number_of_vertices+1:number_of_vertices
    add_vertex!(g)
  end
  for j=old_number_of_vertices+1:number_of_vertices
      neigh = neighbors(config.neighborhood,j,X)
      for i in neigh
          w = weight(config.oracle,i,j,X)
          connect!(g,i,j,w)
      end
  end
end
=#

# Weight functions
constant(k) = (i::Integer, neigh, v, m) = ones(size(m, 2)) * k
ones(i::Integer, neigh, v, m) = ones(size(m, 2))
