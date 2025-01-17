"$(TYPEDEF) Used by GraphIO.jl for several file formats"
struct NestedGraphFormat <: AbstractGraphFormat end

"""
$(TYPEDEF)
$(TYPEDFIELDS)
A `NestedEdge` connects graphs inside a `NestedGraph` or simply nodes inside a `NestedGraph`.
The `NestedEdge` connects two `NestedVertex`s.
This means that every `NestedEdge` connects to a specific node and not as a hyperedge to the whole subgraph graph.
"""
struct NestedEdge{T<:Integer} <: AbstractSimpleEdge{T}
    src::Tuple{T, T}
    dst::Tuple{T, T}
end
NestedEdge(t::Tuple{Tuple{T,T}, Tuple{T,T}}) where {T<:Integer} = NestedEdge(t[1], t[2])
NestedEdge(p::Pair{Tuple{T,T}}) where {T<:Integer} = NestedEdge(p.first, p.second)
NestedEdge(t11::T, t12::T, t21::T, t22::T) where {T<:Integer} = NestedEdge((t11,t12),(t21,t22))
Base.:+(offset::Int, ce::NestedEdge) = NestedEdge(ce.src[1] + offset, ce.src[2], ce.dst[1] + offset, ce.dst[2])

# TODO: convert Tuple{Tuple{T,T}, Tuple{T,T}} where T<Integer to NestedEdge
Base.convert(::Type{NestedEdge}, e::Tuple{Tuple{T,T}, Tuple{T,T}}) where T<:Integer = NestedEdge(e)

"""
$(TYPEDEF)
A `NestedVertex` is the local view of a vertex inside a `NestedGraph`.
It contains the subgraph and the vertex indices.
Basically, it's an alias for a 2-element Tuple.
"""
NestedVertex{T} = Tuple{T,T} where T<:Integer

"""
$(TYPEDEF)
$(TYPEDFIELDS)
A `NestedGraph` is a graph of vertices, where each vertex can be a complete graph.
Connections are done with `NestedEdge`s and the vertices are `NestedVertex`s.
NestedGraphs of NestedGraphs are allowed.
"""
struct NestedGraph{T <: Integer, R <: AbstractGraph{T}, N <: Union{AbstractGraph, AbstractGraph}} <: AbstractGraph{T}
    #TODO modifying flatgr should modify grv, neds & modifying grv neds should modiufy flatgr
    "Flat graph view combining all subgraph graphs given with the edges"
    flatgr::R
    "Original subgraph graphs"
    grv::Vector{N}
    "intersubgraph edges"
    neds::Vector{NestedEdge{T}}
    "Maps the nodes of flat network to the original graph (subgraph, Node)"
    vmap::Vector{Tuple{T,T}}
    # TODO create a synchro Dict{Tuple{Int, Int}, Int} for reverse operation
end

Base.show(io::IO, t::NestedGraph{T,R,N}) where {T,R,N} = print(io, "NestedGraph{$(R),$(N)}({$(nv(t)),$(ne(t))}, $(length(t.grv)) subgraphs)")
NestedGraph{T,R}() where {T,R} = NestedGraph{T,R,R}()
NestedGraph{T,R,N}() where {T,R,N} = NestedGraph(R(), Vector{N}(), Vector{NestedEdge{T}}(), Vector{Tuple{T,T}}())
NestedGraph(::Type{R}) where {R<:AbstractGraph} = NestedGraph(R(), [R()], Vector{NestedEdge{Int}}(), Vector{Tuple{Int,Int}}())
NestedGraph(grv::Vector{T}) where {T<:AbstractGraph} = NestedGraph(grv, Vector{NestedEdge{Int}}())
NestedGraph(gr::T) where {T<:AbstractGraph} = NestedGraph([gr])
function NestedGraph(grv::Vector{R}, edges::AbstractVector; both_ways::Bool=false) where {R<:AbstractGraph}
    nedgs = convert.(NestedEdge, edges)
    flatgrtype = unwraptype(R)
    if !isconcretetype(flatgrtype)
        flatgrtypes = [unwraptype(typeof(gr)) for gr in grv]
        @assert all(==(flatgrtypes[1]), flatgrtypes)
        flatgrtype = flatgrtypes[1]
    end
    flatgr = flatgrtype()
    vmap = Vector{Tuple{Int,Int}}()
    # transfer the graphs to flat graph
    for (i,g) in enumerate(grv)
        shallowcopy_verdges!(flatgr, g)
        [push!(vmap, (i,v)) for v in vertices(g)]
    end
    ng = NestedGraph(flatgr, grv, Vector{NestedEdge{Int}}(), vmap)
    for nedg in nedgs
        add_edge!(ng, nedg)
        both_ways && add_edge!(ng, reverse(nedg))
    end
    return ng
end

"$(TYPEDSIGNATURES) Unwrap NestedGraph to Graph type"
unwraptype(::Type{NestedGraph{T,R}}) where {T,R} = return unwraptype(R)
"$(TYPEDSIGNATURES)"
unwraptype(::Type{NestedGraph{T,R,N}}) where {T,R,N} = return unwraptype(R)
"$(TYPEDSIGNATURES)"
unwraptype(gt::Type{T}) where {T<:AbstractGraph} = return gt

# implement `AbstractTrees` (possibly more in the future)
AbstractTrees.children(node::NestedGraph) = node.grv

Base.getindex(ng::NestedGraph, indx, props::Symbol) = Base.getindex(ng.flatgr, indx, props)

"$(TYPEDSIGNATURES) Convert a local view `NestedVertex` to a global view"
vertex(ng::NestedGraph, cv::NestedVertex) = vertex(ng, cv...)
"$(TYPEDSIGNATURES)"
vertex(ng::NestedGraph, d::T, v::T) where T<:Integer = findfirst(==((d,v)), ng.vmap)

"$(TYPEDSIGNATURES) Get the subgraph index of a vertex `v`"
subgraph(ng::NestedGraph, v::T) where T<:Integer = ng.vmap[v][1]

"$(TYPEDSIGNATURES) Convert a local view `NestedEdge` to a global view"
edge(ng::NestedGraph, ce::NestedEdge) = Edge(vertex(ng, ce.src[1], ce.src[2]), vertex(ng, ce.dst[1], ce.dst[2]))
"$(TYPEDSIGNATURES) Convert a global view of an edge to local view `NestedEdge`"
nestededge(ng::NestedGraph, e::Edge) = NestedEdge(ng.vmap[e.src], ng.vmap[e.dst])
"$(TYPEDSIGNATURES)"
nestedvertex(ng::NestedGraph, v) = ng.vmap[v]
"""
$(TYPEDSIGNATURES) 
Get the subgraph of an edge
If the edge connects 2 subgraphs, it returns `nothing`
"""
subgraphedge(ng::NestedGraph, e::Edge) = issamesubgraph(ng, e.src, e.dst) ? Edge(ng.vmap[e.src][2], ng.vmap[e.dst][2]) : nothing
"$(TYPEDSIGNATURES) Checks if two nodes are in the same subgraph"
issamesubgraph(ng::NestedGraph, v1::Int, v2::Int) = subgraph(ng, v1) == subgraph(ng,v2)
"$(TYPEDSIGNATURES)"
issamesubgraph(ng::NestedGraph, e::Edge) = issamesubgraph(ng, e.src, e.dst) 
"$(TYPEDSIGNATURES)"
issamesubgraph(ce::NestedEdge) = ce.src[1] == ce.dst[1]

"$(TYPEDSIGNATURES) Get all edges that have no subgraph, i.e. that interconnect subgraphs"
intersubgraphedges(ng::NestedGraph) = [e for e in edges(ng) if ng.vmap[e.src][1] != ng.vmap[e.dst][1]]