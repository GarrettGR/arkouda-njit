"""Contains all current Arachne functionality. Includes building methods and algorithmic kernels.
"""
from __future__ import annotations
from typing import cast, Tuple
from typeguard import typechecked
import arachne as ar
from arachne.graphclass import Graph
from arachne.digraphclass import DiGraph
from arachne.propgraphclass import PropGraph
import arkouda as ak
from arkouda.client import generic_msg
from arkouda.pdarrayclass import pdarray, create_pdarray

__all__ = ["read_matrix_market_file",
           "bfs_layers",
           "subgraph_isomorphism",
           "triangles",
           "squares",
           "k_truss",
           "triangle_centrality",
           "connected_components",
           ]

@typechecked
def read_matrix_market_file(filepath: str, 
                            directed = False, 
                            only_edges = False) -> Graph | DiGraph | Tuple:
    """Reads a matrix market file and returns the graph specified by the matrix indices. NOTE: the
    absolute path to the file must be given.

    Returns
    -------
    Graph | DiGraph
        The graph specified by the matrix market file.

    See Also
    --------

    Notes
    -----

    Raises
    ------
    """
    cmd = "readMatrixMarketFile"
    args = { "Path": filepath,
             "Directed": directed }
    rep_msg = generic_msg(cmd=cmd, args=args)
    returned_vals = (cast(str, rep_msg).split('+'))

    src = create_pdarray(returned_vals[0])
    dst = create_pdarray(returned_vals[1])

    if only_edges:
        return (src,dst)

    wgt = ak.array([-1])
    weighted = False
    if returned_vals[2].strip() != "nil":
        wgt = create_pdarray(returned_vals[2])
        weighted = True

    if not directed:
        graph = Graph()
        if not weighted:
            graph.add_edges_from(src, dst)
        else:
            graph.add_edges_from(src, dst, wgt)
        return graph
    else:
        di_graph = DiGraph()
        if not weighted:
            di_graph.add_edges_from(src, dst)
        else:
            di_graph.add_edges_from(src, dst, wgt)
        return di_graph

@typechecked
def bfs_layers(graph: ar.Graph | ar.DiGraph, source: int) -> pdarray:
    """ This function generates the breadth-first search sequence of the vertices in a given graph
    starting from the given source vertex.

    Parameters
    ----------
    graph : ar.Graph | ar.DiGraph
        The graph whose breadth-first search layers we want.
    source : int
        Starting vertex for breadth-first search.
        
    Returns
    -------
    pdarray
        The depth of each vertex in relation to the source vertex. NOTE: The indices of the returned
        array correspond to the internal Chapel server vertex values. To properly index, the user
        must perform a find operation on "graph.nodes()" adn then use the returned pdarray to index
        into depths.
    """
    cmd = "segmentedGraphBFS"
    args = { "GraphName":graph.name,
             "Source":source }

    repMsg = generic_msg(cmd=cmd, args=args)
    return create_pdarray(repMsg)

@typechecked
def triangles(graph: ar.Graph, vertices: pdarray = None) -> int | pdarray:
    """
    Returns the number of triangles in a graph. If `vertices` exists and is nonempty, it returns the
    number of triangles that each vertex in `vertices` takes a part of. For example, if the input
    `vertices` contains `[0, 10, 40]` and it returns `[3, 20, 5]` then it means that 3 triangles
    contain vertex 0, 20 contain vertex 10, and 5 contain vertex 40.

    Note: Keeps in line with NetworkX triangles function where the returned value has to be divided
    3.

    Parameters
    ----------
    graph : Graph
        The graph whose triangles we want to find.
    vertices : pdarray
        Optional, if we only want to find triangles on specific vertices.
    
    Returns
    -------
    pdarray
        The total number of triangles.
    
    See Also
    --------
    squares, triangle_centrality, k-truss
    
    Notes
    -----
    
    Raises
    ------  
    RuntimeError
    """
    cmd = "segmentedGraphTri"

    if vertices is not None:
        vertices = ak.find(vertices, graph.nodes())
        not_found = vertices == -1
        vertices = vertices[~not_found]
    else:
        vertices = ak.array([-1])

    args = { "GraphName":graph.name,
             "VerticesName":vertices.name}

    rep_msg = generic_msg(cmd=cmd,args=args)
    if rep_msg.find("created") == -1:
        return int(rep_msg)
    return create_pdarray(rep_msg)

@typechecked
def squares(graph: Graph) -> int:
    """
    This function will return the number of squares in an undirected graph.

    Parameters
    ----------
    graph : Graph
        An undirected graph whose number of squares are to be returned
    
    Returns
    -------
    int
        The total number of squares
    
    See Also
    --------
    triangles
    
    Raises
    ------  
    RuntimeError
    """
    degree = graph.degree()
    cmd = "segmentedGraphSquares"
    args = { "GraphName" : graph.name,
             "DegreeName" : degree.name }
    rep_msg = generic_msg(cmd=cmd,args=args)
    return int(rep_msg)

@typechecked
def triangle_centrality(graph: ar.Graph) -> pdarray:
    """
    Given a graph, returns the triangle centrality for each node of the graph. The triangle 
    centrality of a node is given by the number of triangles that surround a particular node. It is
    based off the paper by Paul Burkardt (https://arxiv.org/abs/2105.00110). 

    Parameters
    ----------
    G : ar.Graph
        Main undirected graph that will be searched into.

    Returns
    -------
    pdarray
        Array that is the same size of the number of vertices where each element is the triangle 
        centrality measure.
    """
    cmd = "TriangleCentrality"
    args = {"GraphName" : graph.name}

    rep_msg = generic_msg(cmd=cmd,args=args)
    return create_pdarray(rep_msg)

@typechecked
def k_truss(graph: Graph, kTrussValue:int) -> pdarray:
    """
    This function returns the number of triangles in a static graph for each edge that satisfies the
    k requirement.
    
    Returns
    -------
    pdarray
        The total number of triangles incident to each edge.
    
    See Also
    --------
    
    Notes
    -----
    
    Raises
    ------  
    RuntimeError
    """
    cmd = "segmentedTruss"
    args = { "KValue":kTrussValue,
             "NumOfVertices":graph.n_vertices,
             "NumOfEdges":graph.n_edges,
             "Directed":graph.directed,
             "Weighted": graph.weighted,
             "GraphName":graph.name }

    repMsg = generic_msg(cmd=cmd,args=args)
    return create_pdarray(repMsg)

@typechecked
def connected_components(graph: Graph) -> pdarray:
    """ This function generates the connected components of a given graph.
    
    Returns
    -------
    pdarray
        The label of the component each vertex belongs to.
    
    See Also
    --------
    
    Notes
    -----
    
    Raises
    ------  
    RuntimeError
    """
    cmd = "segmentedGraphCC"
    args = { "GraphName":graph.name }
    
    repMsg = generic_msg(cmd=cmd, args=args)
    return create_pdarray(repMsg)

@typechecked
def subgraph_isomorphism(graph: PropGraph, subgraph: PropGraph) -> pdarray:
    """
    Given a graph and a subgraph, perform a search in graph matching all possible subgraphs that
    are isomorphic to the subgraph. Uses implementation of the VF2 algorithm 
    (https://ieeexplore.ieee.org/document/1323804).

    Parameters
    ----------
    G : PropGraph | DiGraph
        Main graph that will be searched into. 
    H : PropGraph | DiGraph
        Subgraph (pattern) that will be searched for.

    Returns
    -------
    pdarray
        Mappings of vertices from graph that match the vertices in subgraph. If there are `n` 
        vertices in the subgraph and the graph has `k` subgraphs that are isomorphic, then the size
        of the returned `pdarray` is `nk`. The array can be thought of as a segmented array where 
        slices of size `k` will give a complete subgraph from the main graph as long as they are 
        made with the assumption that the array starts at index 0.
    
    See Also
    --------
    triangles, k_truss

    Notes
    -----
    The vertices of the subgraph are remapped to a one-up range starting from 0 and this is how they
    are portrayed in the returned `pdarray`. The graph vertices are also remapped internally BUT
    the returned mappings are the original vertex values of the graph.
    """
    cmd = "subgraphIsomorphism"
    args = { "MainGraphName":graph.name,
             "SubGraphName":subgraph.name }

    rep_msg = generic_msg(cmd=cmd, args=args)
    return create_pdarray(rep_msg)
