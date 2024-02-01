module SubgraphIsomorphism {
    // Chapel modules.
    use Reflection;
    use List;
    use Random;
    use List;
    use IO;
    use Time;
    use Set;
    use Map;

    // Arachne modules.
    use GraphArray;
    use Utils;
    
    // Arkouda modules.
    use MultiTypeSymbolTable;
    use MultiTypeSymEntry;
    use ServerConfig;
    use AryUtil;
    use SegStringSort;
    use SegmentedString;

    /** Executes the VF2 subgraph isomorphism finding procedure. Instances of the subgraph `g2` are
    searched for amongst the subgraphs of `g1` and the isomorphic ones are returned through an
    array that maps the isomorphic vertices of `g1` to those of `g2`.*/
    proc runVF2 (g1: SegGraph, g2: SegGraph, st: borrowed SymTab):[] int throws {
        var TimerArrNew:[0..30] real(64) = 0.0;
        var numIso: int = 0;
        var timerpreproc:stopwatch;
        timerpreproc.start();

        // Extract the g1/G/g information from the SegGraph data structure.
        var srcNodesG1Dist = toSymEntry(g1.getComp("SRC"), int).a;
        var dstNodesG1Dist = toSymEntry(g1.getComp("DST"), int).a;
        var segGraphG1Dist = toSymEntry(g1.getComp("SEGMENTS"), int).a;
        var srcRG1Dist = toSymEntry(g1.getComp("SRC_R"), int).a;
        var dstRG1Dist = toSymEntry(g1.getComp("DST_R"), int).a;
        var segRG1Dist = toSymEntry(g1.getComp("SEGMENTS_R"), int).a;
        var nodeMapGraphG1Dist = toSymEntry(g1.getComp("VERTEX_MAP"), int).a;

        // Extract the g2/H/h information from the SegGraph data structure.
        var srcNodesG2Dist = toSymEntry(g2.getComp("SRC"), int).a;
        var dstNodesG2Dist = toSymEntry(g2.getComp("DST"), int).a;
        var segGraphG2Dist = toSymEntry(g2.getComp("SEGMENTS"), int).a;
        var srcRG2Dist = toSymEntry(g2.getComp("SRC_R"), int).a;
        var dstRG2Dist = toSymEntry(g2.getComp("DST_R"), int).a;
        var segRG2Dist = toSymEntry(g2.getComp("SEGMENTS_R"), int).a;
        var nodeMapGraphG2Dist = toSymEntry(g2.getComp("VERTEX_MAP"), int).a;

        var nG1 = nodeMapGraphG1Dist.size;
        var mG1 = srcNodesG1Dist.size;
        var nG2 = nodeMapGraphG2Dist.size;
        var mG2 = srcNodesG2Dist.size;

        //******************************************************************************************
        //******************************************************************************************
        // OLIVER NOTE: 
        // Relabeled node labels and edge relationships id values so those of H match those of G to 
        // speed up semantic checks. 
        // 
        // In the SegGraph data structure for property graphs, there could be many different types 
        // of labels and relationships. Therefore, we will do some preprocessing here to relabel
        // all labels and relationships and place them into sets for quick intersections.
        //
        // This assumes that all labels and relationships are strings BUT some labels and 
        // relationships can be unsigned or regular integers. If this is the case then borrowed 
        // SegStringSymEntry below would be empty. We currently do not do a check for this since all
        // of our test data has string labels and relationships BUT we should fix this in the 
        // future. 
        //
        // All of the code contained between the //**** comments (roughly ~100 lines) should
        // probably eventually be a function that lives where SegGraph is defined to perform a 
        // globalized relabeling and creating arrays of sets to speed up comparing the labels and
        // relationships of two or more different graphs.
        var edgeRelationshipsGraphG1 = (g1.getComp("EDGE_RELATIONSHIPS"):(borrowed MapSymEntry(string, (string, borrowed SegStringSymEntry)))).stored_map;
        var nodeLabelsGraphG1 = (g1.getComp("VERTEX_LABELS"):(borrowed MapSymEntry(string, (string, borrowed SegStringSymEntry)))).stored_map;

        var edgeRelationshipsGraphG2 = (g2.getComp("EDGE_RELATIONSHIPS"):(borrowed MapSymEntry(string, (string, borrowed SegStringSymEntry)))).stored_map;
        var nodeLabelsGraphG2 = (g2.getComp("VERTEX_LABELS"):(borrowed MapSymEntry(string, (string, borrowed SegStringSymEntry)))).stored_map;

        var relationshipStringToInt, labelStringToInt = new map(string, int); 

        // Create global relationship mapper for G1 and G2.
        var id = 0;
        for k in edgeRelationshipsGraphG1.keys() {
            var segString = getSegString(edgeRelationshipsGraphG1[k][1].name, st);
            for i in 0..segString.size-1 {
                var val = segString[i];
                if !relationshipStringToInt.contains(val) {
                    relationshipStringToInt.add(val, id);
                    id += 1;
                }
            }
        }
        for k in edgeRelationshipsGraphG2.keys() {
            var segString = getSegString(edgeRelationshipsGraphG2[k][1].name, st);
            for i in 0..edgeRelationshipsGraphG2[k][1].size-1 {
                var val = segString[i];
                if !relationshipStringToInt.contains(val) {
                    relationshipStringToInt.add(val, id);
                    id += 1;
                }
            }
        }
        
        // Create global label mapper for G1 and G2.
        id = 0;
        for k in nodeLabelsGraphG1.keys() {
            var segString = getSegString(nodeLabelsGraphG1[k][1].name, st);
            for i in 0..nodeLabelsGraphG1[k][1].size-1 {
                var val = segString[i];
                if !labelStringToInt.contains(val) {
                    labelStringToInt.add(val, id);
                    id += 1;
                }
            }
        }
        for k in nodeLabelsGraphG2.keys() {
            var segString = getSegString(nodeLabelsGraphG2[k][1].name, st);
            for i in 0..nodeLabelsGraphG2[k][1].size-1 {
                var val = segString[i];
                if !labelStringToInt.contains(val) {
                    labelStringToInt.add(val, id);
                    id += 1;
                }
            }
        }

        // Create new "arrays of sets" to make semantic checks quicker by allowing usage of Chapel's
        // internal hash table intersections via sets.
        var convertedRelationshipsG1Dist = makeDistArray(g1.n_edges, domain(int));
        var convertedRelationshipsG2Dist = makeDistArray(g2.n_edges, domain(int));
        var convertedLabelsG1Dist = makeDistArray(g1.n_vertices, domain(int));
        var convertedLabelsG2Dist = makeDistArray(g2.n_vertices, domain(int));

        for (k,v) in zip(edgeRelationshipsGraphG1.keys(), edgeRelationshipsGraphG1.values()) {
            var arr = toSymEntry(getGenericTypedArrayEntry(k,st), int).a;
            var mapper = getSegString(v[1].name,st);
            forall (x,i) in zip(arr, arr.domain) do convertedRelationshipsG1Dist[i].add(relationshipStringToInt[mapper[x]]);
        }

        for (k,v) in zip(edgeRelationshipsGraphG2.keys(), edgeRelationshipsGraphG2.values()) {
            var arr = toSymEntry(getGenericTypedArrayEntry(k,st), int).a;
            var mapper = getSegString(v[1].name,st);
            forall (x,i) in zip(arr, arr.domain) do convertedRelationshipsG2Dist[i].add(relationshipStringToInt[mapper[x]]);
        }

        for (k,v) in zip(nodeLabelsGraphG1.keys(), nodeLabelsGraphG1.values()) {
            var arr = toSymEntry(getGenericTypedArrayEntry(k,st), int).a;
            var mapper = getSegString(v[1].name,st);
            forall (x,i) in zip(arr, arr.domain) do convertedLabelsG1Dist[i].add(labelStringToInt[mapper[x]]);
        }

        for (k,v) in zip(nodeLabelsGraphG2.keys(), nodeLabelsGraphG2.values()) {
            var arr = toSymEntry(getGenericTypedArrayEntry(k,st), int).a;
            var mapper = getSegString(v[1].name,st);
            forall (x,i) in zip(arr, arr.domain) do convertedLabelsG2Dist[i].add(labelStringToInt[mapper[x]]);
        }
        //******************************************************************************************
        //******************************************************************************************

        //************************************LOCALIZATION******************************************
        var srcNodesG1: [0..<mG1] int = srcNodesG1Dist;
        var dstNodesG1: [0..<mG1] int = dstNodesG1Dist;
        var segGraphG1: [0..<nG1+1] int = segGraphG1Dist;
        var srcRG1: [0..<mG1] int = srcRG1Dist;
        var dstRG1: [0..<mG1] int = dstRG1Dist;
        var segRG1: [0..<nG1+1] int = segRG1Dist;
        var nodeMapGraphG1: [0..<nG1] int = nodeMapGraphG1Dist;
        var convertedRelationshipsG1: [0..<mG1] domain(int) = convertedRelationshipsG1Dist;
        var convertedLabelsG1: [0..<nG1] domain(int) = convertedLabelsG1Dist;

        var srcNodesG2: [0..<mG2] int = srcNodesG2Dist;
        var dstNodesG2: [0..<mG2] int = dstNodesG2Dist;
        var segGraphG2: [0..<nG2+1] int = segGraphG2Dist;
        var srcRG2: [0..<mG2] int = srcRG2Dist;
        var dstRG2: [0..<mG2] int = dstRG2Dist;
        var segRG2: [0..<nG2+1] int = segRG2Dist;
        var nodeMapGraphG2: [0..<nG2] int = nodeMapGraphG2Dist;
        var convertedRelationshipsG2: [0..<mG2] domain(int) = convertedRelationshipsG2Dist;
        var convertedLabelsG2: [0..<nG2] domain(int) = convertedLabelsG2Dist;
        //******************************************************************************************

        timerpreproc.stop();
        TimerArrNew[0] += timerpreproc.elapsed();
        
        var timerVF2:stopwatch;
        timerVF2.start();
        var IsoArrtemp = vf2(g1, g2);
        timerVF2.stop();
        TimerArrNew[1] += timerVF2.elapsed();

        var IsoArr = nodeMapGraphG1[IsoArrtemp]; // Map vertices back to original values.

        /** Returns the set of internal identifiers of relationships for a given edge. Performs a 
        binary search into the the given `dst` array of a graph.*/
        // proc getRelationships(ref seg, ref dst, ref edgeRelationships, fromNode:int, toNode:int) throws {
        //     var found: bool = false;
        //     var start = seg[fromNode];
        //     var end = seg[fromNode+1]-1;
            
        //     var edgeFound = bin_search_v(dst, start, end, toNode);
        //     var emptyRels = domain(int);

        //     if edgeFound > -1 then {
        //         found = true; 
        //         var foundRels = edgeRelationships[edgeFound];
        //         return(found, foundRels);
        //     }
        //     return (found, emptyRels);
        // }

        /** Returns the set of internal identifiers of labels for a given vertex.*/
        // proc getLabels(node:int, ref nodeLabels) throws {
        //     var found : bool = false;
        //     var emptyLabels = domain(int);

        //     try {
        //         var foundLabels = nodeLabels[node];
        //         found = true;
        //         return(found, foundLabels);
        //     }
            
        //     return (found, emptyLabels);
        // }
        var core1:[0..g1.n_vertices-1] int = -1;
        var Tin1:[0..g1.n_vertices-1] int = -1;
        var Tout1:[0..g1.n_vertices-1] int = -1;

        var core2:[0..g2.n_vertices-1] int = -1;
        var Tin2:[0..g2.n_vertices-1] int = -1;
        var Tout2:[0..g2.n_vertices-1] int = -1;
        

        /** Keeps track of the isomorphic mapping state during the execution process of VF2.*/
        record State {
            //var n1, n2: int;
            //var core1, core2:  map(int, int);
            ////////////////////////////////////////////////////////var core:[0..g2.n_vertices-1] int;
            var core:[0..3] int;
            //var mapping: set((int , int)); 

            // NOTE: Not used, saved for future work to automatically return true once we reach 
            // depth equal to the subgraph size.
            var depth: int;
            
            // NOTE: Not used, saved for future work to allow comparison of edge weights and 
            // attributes to only return the subgraphs that are less than the given cost. 
            //var cost: real;

            // Tin tracks in-neighbors - nodes with edges to current partial mapping.
            // Tout tracks out-neighbors - nodes with edges from current mapping.
            var Tin1, Tout1, Tin2, Tout2: domain(int);

            /** State initializer.*/
            proc init() {
                //this.n1 = 0;
                //this.n2 = 0;
                //this.core1 = new map(int, int);
                //this.core2 = new map(int, int);
                this.core = -1;  // Initialize all elements to -1
                //this.mapping = new set((int, int));
                this.depth = 0;
                //this.cost = 0.0;
                this.Tin1  =  {1..0};
                this.Tout1 =  {1..0};
                this.Tin2  =  {1..0};
                this.Tout2 =  {1..0};
            }

            /** Initialized based on given sizes `n1` and `n2`.*/


            /** Copy current state information to a new state.*/
            proc copy() {
                var state = new State();
                //state.core1 = this.core1;
                //state.core2 = this.core2;
                state.core = this.core;
                //state.mapping = this.mapping;  
                state.depth = this.depth;
                //state.cost = this.cost;
                state.Tin1 = this.Tin1;
                state.Tout1 = this.Tout1;
                state.Tin2 = this.Tin2;
                state.Tout2 = this.Tout2;
                return state;
            }

            /** Reset vectors during backtracking.*/
/*            proc reset() {
                //this.mapping.clear(); // reset to empty
                //this.core1.clear();
                //this.core2.clear();
                this.core = -1;
                //this.depth -= 1;
                //this.cost -= 1;
                this.Tin1.clear();
                this.Tout1.clear();
                this.Tin2.clear();
                this.Tout2.clear(); 
            }*/
            
            /** Add a vertex pair `(x1, x2)` to the mapping.*/
            proc addPair(x1: int, x2: int) {
                //this.core1.add(x1, x2);
                //this.core2.add(x2, x1);
                this.core[x2] = x1;  // Map x2 in g2 to x1 in g1
                //this.mapping.add((x1, x2));
                this.depth += 1;
            }

            /** Check if a given node is mapped in g1.*/
            proc isMappedn1(n1: int): bool {
                //if this.core1.contains(node) then return true;
                //else return false;
                for val in this.core {
                    if val == n1 {
                        return true;
                    }
                }
                return false;
            }
            
            /** Check if a given node is mapped in g2.*/
            proc isMappedn2(n2: int): bool {
                //if this.core2.contains(node) then return true;
                //else return false;
                return (this.core[n2] != -1);  // Check if the node is mapped in g2
            }
            
            proc addToTinTout (u: int, v: int){
                var timeraddToTinToutinside:stopwatch;
                timeraddToTinToutinside.start();

                ref inNeighbors = dstRG1[segRG1[u]..<segRG1[u+1]];
                ref outNeighbors = dstNodesG1[segGraphG1[u]..<segGraphG1[u+1]];
                
                this.Tin1.remove(u);
                this.Tout1.remove(u);
                
                for n1 in inNeighbors do if !this.isMappedn1(n1) then this.Tin1.add(n1);
                for n1 in outNeighbors do if !this.isMappedn1(n1) then this.Tout1.add(n1);
                
                ref inNeighborsg2 = dstRG2[segRG2[v]..<segRG2[v+1]];            
                ref outNeighborsg2 = dstNodesG2[segGraphG2[v]..<segGraphG2[v+1]];

                this.Tin2.remove(v);
                this.Tout2.remove(v);
            
                for n2 in inNeighborsg2 do if this.core(n2) == -1 then this.Tin2.add(n2);
                for n2 in outNeighborsg2 do if this.core(n2) == -1 then this.Tout2.add(n2);
                            
                timeraddToTinToutinside.stop();
                TimerArrNew[21] += timeraddToTinToutinside.elapsed();
                return ;
            }
/*
            proc isFeasible(n1: int, n2: int) throws {
                var timerisFeasible:stopwatch;
                timerisFeasible.start();

                var termout1, termout2, termin1, termin2, new1, new2 : int = 0;


                
                // Get out neighbors of G1 and G2
                var getOutN1 = dstNodesG1[segGraphG1[n1]..<segGraphG1[n1+1]];
                var getOutN2 = dstNodesG2[segGraphG2[n2]..<segGraphG2[n2+1]];
            
                // Check out neighbors of n2 
                for Out2 in getOutN2 {
                    //if state.isMappedn2(Out2) {
                    if this.core(Out2) != -1 {
                        //var Out1 = state.core2(Out2);
                        var Out1 = this.core(Out2);
                        var eid1 = getEdgeId(n1, Out1, dstNodesG1, segGraphG1);
                        var eid2 = getEdgeId(n2, Out2, dstNodesG2, segGraphG2);

                        // var (flag1, label1) = getRelationships(segGraphG1, dstNodesG1, convertedRelationshipsG1, n1, Out1);
                        // var (flag2, label2) = getRelationships(segGraphG2, dstNodesG2, convertedRelationshipsG2, n2, Out2);

                        if eid1 == -1 || eid2 == -1 {
                            timerisFeasible.stop();
                            TimerArrNew[2] += timerisFeasible.elapsed();
                            return false;
                        }

                        // var label1 = convertedRelationshipsG1[eid1];
                        // var label2 = convertedRelationshipsG2[eid2];
                        var relationshipsG1eid1 = convertedRelationshipsG1[eid1];
                        var relationshipsG2eid2 = convertedRelationshipsG2[eid2];
                        // var intersection = relationshipsG1eid1 & relationshipsG2eid2;
                
                        // if intersection.size <= 0 {
                        if relationshipsG1eid1 != relationshipsG2eid2 {;
                            timerisFeasible.stop();
                            TimerArrNew[2] += timerisFeasible.elapsed();
                            return false;
                        }
                    } 
                    else {
                        if this.Tin2.contains(Out2) then termin2 += 1;
                        if this.Tout2.contains(Out2) then termout2 += 1;
                        if !this.Tin2.contains(Out2) && !this.Tout2.contains(Out2) then new2 += 1;
                    }
                }
                
                // Get in neighbors of G1 and G2
                var getInN1 = dstRG1[segRG1[n1]..<segRG1[n1+1]];
                var getInN2 = dstRG2[segRG2[n2]..<segRG2[n2+1]];

                // Check in neighbors of n2 
                for In2 in getInN2 {
                    if this.isMappedn2(In2) {
                        //var In1 = state.core2(In2);
                        var In1 = this.core(In2);
                        var eid1 = getEdgeId(In1, n1, dstNodesG1, segGraphG1);
                        var eid2 = getEdgeId(In2, n2, dstNodesG2, segGraphG2);
                        
                        // var (flag1, label1) = getRelationships(segGraphG1, dstNodesG1, convertedRelationshipsG1, In1, n1);
                        // var (flag2, label2) = getRelationships(segGraphG2, dstNodesG2, convertedRelationshipsG2, In2, n2);

                        if eid1 == -1 || eid2 == -1 {
                            timerisFeasible.stop();
                            TimerArrNew[2] += timerisFeasible.elapsed();
                            return false;
                        }

                        // var label1 = convertedRelationshipsG1[eid1];
                        // var label2 = convertedRelationshipsG2[eid2];
                        var relationshipsG1eid1 = convertedRelationshipsG1[eid1];
                        var relationshipsG2eid2 = convertedRelationshipsG2[eid2];
                        //var intersection = relationshipsG1eid1 & relationshipsG2eid2;
                
                        // if intersection.size <= 0 {
                        if relationshipsG1eid1 != relationshipsG2eid2 {;
                            timerisFeasible.stop();
                            TimerArrNew[2] += timerisFeasible.elapsed();
                            return false;
                        }
                    }
                    else {
                        if this.Tin2.contains(In2) then termin2 += 1;
                        if this.Tout2.contains(In2) then termout2 += 1;
                        if !this.Tin2.contains(In2) && !this.Tout2.contains(In2) then new2 += 1;
                    }
                }
                
                // Check out neighbors of n1 
                for Out1 in getOutN1 {
                    if !this.isMappedn1(Out1) {
                        if this.Tin1.contains(Out1) then termin1 += 1;
                        if this.Tout1.contains(Out1) then termout1 += 1;
                        if !this.Tin1.contains(Out1) && !this.Tout1.contains(Out1) then new1 += 1;
                    }
                }
                
                // Check in neighbors of n1 
                for In1 in getInN1 {
                    if !this.isMappedn1(In1) {
                        if this.Tin1.contains(In1) then termin1 += 1;
                        if this.Tout1.contains(In1) then termout1 += 1;
                        if !this.Tin1.contains(In1) && !this.Tout1.contains(In1) then new1 += 1;
                    }
                }
                timerisFeasible.stop();
                TimerArrNew[2] += timerisFeasible.elapsed();
                if !(termin2<=termin1 && termout2<=termout1 && (termin2+termout2+new2)<=(termin1+termout1+new1)) {
                    return false;
                }


                ////Label check
                if !nodesLabelCompatible(n1, n2) {
                    timerisFeasible.stop();
                    TimerArrNew[2] += timerisFeasible.elapsed();
                    return false;
                }

                return true;
            } // end of isFeasible
*/
        } //end of State record

        /**Find vertices that point to this state and all vertices that this state points to.*/
/*        proc addToTinTout(ref state: State, u: int, v: int): State throws {
            var timeraddto1:stopwatch;
            timeraddto1.start();
            ref inNeighbors = dstRG1[segRG1[u]..<segRG1[u+1]];
            ref outNeighbors = dstNodesG1[segGraphG1[u]..<segGraphG1[u+1]];
            timeraddto1.stop();
            TimerArrNew[12] += timeraddto1.elapsed();
            // Add neighbors of u to Tin1 and Tout1 from g1
            // if state.Tin1.contains(u) then state.Tin1.remove(u);
            // if state.Tout1.contains(u) then state.Tout1.remove(u);
            var timeraddto2:stopwatch;
            timeraddto2.start();
            state.Tin1.remove(u);
            state.Tout1.remove(u);
            timeraddto2.stop();
            TimerArrNew[13] += timeraddto2.elapsed();
            
            // Add unmapped neighbors to Tin1
            var timeraddto3:stopwatch;
            timeraddto3.start();
            
            //for n1 in inNeighbors do if !state.core1.contains(n1) then state.Tin1.add(n1);
            for n1 in inNeighbors do if !state.isMappedn1(n1) then state.Tin1.add(n1);

            timeraddto3.stop();
            TimerArrNew[14] += timeraddto3.elapsed();
            // Add unmapped neighbors to Tout1
            var timeraddto4:stopwatch;
            timeraddto4.start();

            
            //for n1 in outNeighbors do if !state.core1.contains(n1) then state.Tout1.add(n1);
            for n1 in outNeighbors do if !state.isMappedn1(n1) then state.Tout1.add(n1);

            timeraddto4.stop();
            TimerArrNew[15] += timeraddto4.elapsed();
            // Add neighbors of v to Tin2, Tout2 from g2
            var timeraddto5:stopwatch;
            timeraddto5.start();

            
            ref inNeighborsg2 = dstRG2[segRG2[v]..<segRG2[v+1]];            
            ref outNeighborsg2 = dstNodesG2[segGraphG2[v]..<segGraphG2[v+1]];


            timeraddto5.stop();
            TimerArrNew[16] += timeraddto5.elapsed();
            // if state.Tin2.contains(v) then state.Tin2.remove(v);
            // if state.Tout2.contains(v) then state.Tout2.remove(v);
            var timeraddto6:stopwatch;
            timeraddto6.start();

            state.Tin2.remove(v);
            state.Tout2.remove(v);

            timeraddto6.stop();
            TimerArrNew[17] += timeraddto6.elapsed();
            // Add unmapped neighbors to Tin2
            var timeraddto7:stopwatch;
            timeraddto7.start();

            
            //for n2 in inNeighborsg2 do if !state.core2.contains(n2) then state.Tin2.add(n2);
            for n2 in inNeighborsg2 do if state.core(n2) == -1 then state.Tin2.add(n2);


            timeraddto7.stop();
            TimerArrNew[18] += timeraddto7.elapsed();
            // Add unmapped neighbors to Tout2
            var timeraddto8:stopwatch;
            timeraddto8.start();

            
            //for n2 in outNeighborsg2 do if !state.core2.contains(n2) then state.Tout2.add(n2);
            for n2 in outNeighborsg2 do if state.core(n2) == -1 then state.Tout2.add(n2);
            timeraddto8.stop();
            TimerArrNew[19] += timeraddto8.elapsed();
            return state;
        } // end of addToTinTout
*/
        /** Creates an initial, empty state. NOTE: Is this needed?*/
        proc createInitialState(): State throws {
            var state = new State();
            state.init();
            return state;
        }  //end of createInitialState

        /** Returns unmapped nodes for the current state of the subgraph.*/
        proc getUnmappedSubgraphNodes(graph, state) throws {
            var unmapped: list(int);
            for n in 0..<graph.n_vertices do if !state.isMappedn2(n) then unmapped.pushBack(n);
            return unmapped;
        } // end of getUnmappedSubgraphNodes
        
        /** Returns unmapped nodes for the current state of the graph.*/
        proc getUnmappedGraphNodes(graph: SegGraph, state: State) throws {
            var unmapped: list(int) = 0..#graph.n_vertices;
            //for key in state.core1.keys() do unmapped.remove(key);
            for key in state.core do unmapped.remove(key);
            return unmapped;
        } // end of getUnmappedGraphNodes
 
        /** Create candidates based on current state and retuns a set of pairs.*/
        proc getCandidatePairsOpti(state:State) throws {
            //var timergetCandidatePairsOpti:stopwatch;
            //timergetCandidatePairsOpti.start();
            
            //var candidates = new set((int, int), parSafe = true);
            //var timerunmapped:stopwatch;
            //timerunmapped.start();
            var candidateG2: int = -1;
            var flag : bool = false;
            var unmapped = getUnmappedSubgraphNodes(g2, state);

            //timerunmapped.stop();
            //TimerArrNew[5] += timerunmapped.elapsed();

            var idex: int = 0;
            // If Tout1 and Tout2 are both nonempty.
            if state.Tout1.size > 0 && state.Tout2.size > 0 {
                var minTout2 = min reduce state.Tout2;

                var candidateG1:[0..state.Tout1.size-1] int;
                candidateG2 = minTout2;
                
                idex = 0;
                for elem in state.Tout1 {
                //for n1 in state.Tout1 {
                    //candidates.add((n1, minTout2));
                    candidateG1[idex] = elem;
                    idex += 1;
                }
                return (candidateG1, candidateG2, true) ;

            } else {
                //If Tin1 and Tin2 are both nonempty.
                if state.Tin1.size > 0 && state.Tin2.size > 0 {
                    var minTin2 = min reduce state.Tin2;
                    var candidateG1:[0..state.Tin1.size-1] int;
                    candidateG2 = minTin2;

                    idex = 0;
                    for elem in state.Tin1 {
                    //for n1 in state.Tin1 {
                        //candidates.add((n1, minTin2));
                        candidateG1[idex] = elem;
                        idex += 1;
                    }
                    return (candidateG1, candidateG2, true) ;

                } else { // not (Tin1 or Tin2) NOTE: What does this mean?
                    if unmapped.size > 0 {
                        var minUnmapped2 = min reduce unmapped;
                        var unmappedG1 = getUnmappedGraphNodes(g1, state);
                        
                        var candidateG1:[0..unmappedG1.size-1] int;
                        candidateG2 = minUnmapped2;

                        idex = 0;
                        for elem in unmappedG1 {
                        //for umg1 in unmappedG1 {
                            //candidates.add((umg1,minUnmapped2));
                            candidateG1 [idex] = elem;
                            idex += 1;
                        } 
                        //for n1 in 0..#g1.n_vertices do if !state.core1.contains(n1) then candidates.add((n1, minUnmapped));
                        return (candidateG1, candidateG2, true) ;
                    }

                } 
            }   
            //timergetCandidatePairsOpti.stop();
            //TimerArrNew[7] += timergetCandidatePairsOpti.elapsed();
            var candidateG1: [0..0] int = -1;

            return (candidateG1, candidateG2, flag) ;
        } // end of getCandidatePairsOpti


        /** Check that node labels are the same.*/
        proc nodesLabelCompatible(n1: int, n2: int): bool throws {
            var timernodesLabelCompatible:stopwatch;
            timernodesLabelCompatible.start();

            // var label1 = getLabels(n1, convertedLabelsG1)[1];
            // var label2 = getLabels(n2, convertedLabelsG2)[1];
            // var label1 = convertedLabelsG1[n1];
            // var label2 = convertedLabelsG2[n2];

            var labelsG1n1 = convertedLabelsG1[n1];
            var labelsG2n2 = convertedLabelsG2[n2];
            //var intersection = labelsG1n1 & labelsG2n2;

            // if intersection.size <= 0 {
            if labelsG1n1 != labelsG2n2 {
                timernodesLabelCompatible.stop();
                TimerArrNew[4] += timernodesLabelCompatible.elapsed();                
                return false;
            }
            timernodesLabelCompatible.stop();
            TimerArrNew[4] += timernodesLabelCompatible.elapsed();
            return true;
        } // end of nodesLabelCompatible

        /** Check if a pair of candidates are feasible.*/
        proc isFeasible(state: State, n1: int, n2: int) throws {
            var timerisFeasible:stopwatch;
            timerisFeasible.start();

            var termout1, termout2, termin1, termin2, new1, new2 : int = 0;


            
            // Get out neighbors of G1 and G2
            var getOutN1 = dstNodesG1[segGraphG1[n1]..<segGraphG1[n1+1]];
            var getOutN2 = dstNodesG2[segGraphG2[n2]..<segGraphG2[n2+1]];
         
            // Check out neighbors of n2 
            for Out2 in getOutN2 {
                //if state.isMappedn2(Out2) {
                if state.core(Out2) != -1 {
                    //var Out1 = state.core2(Out2);
                    var Out1 = state.core(Out2);
                    var eid1 = getEdgeId(n1, Out1, dstNodesG1, segGraphG1);
                    var eid2 = getEdgeId(n2, Out2, dstNodesG2, segGraphG2);

                    // var (flag1, label1) = getRelationships(segGraphG1, dstNodesG1, convertedRelationshipsG1, n1, Out1);
                    // var (flag2, label2) = getRelationships(segGraphG2, dstNodesG2, convertedRelationshipsG2, n2, Out2);

                    if eid1 == -1 || eid2 == -1 {
                        timerisFeasible.stop();
                        TimerArrNew[2] += timerisFeasible.elapsed();
                        return false;
                    }

                    // var label1 = convertedRelationshipsG1[eid1];
                    // var label2 = convertedRelationshipsG2[eid2];
                    var relationshipsG1eid1 = convertedRelationshipsG1[eid1];
                    var relationshipsG2eid2 = convertedRelationshipsG2[eid2];
                    // var intersection = relationshipsG1eid1 & relationshipsG2eid2;
            
                    // if intersection.size <= 0 {
                    if relationshipsG1eid1 != relationshipsG2eid2 {;
                        timerisFeasible.stop();
                        TimerArrNew[2] += timerisFeasible.elapsed();
                        return false;
                    }
                } 
                else {
                    if state.Tin2.contains(Out2) then termin2 += 1;
                    if state.Tout2.contains(Out2) then termout2 += 1;
                    if !state.Tin2.contains(Out2) && !state.Tout2.contains(Out2) then new2 += 1;
                }
            }
            
            // Get in neighbors of G1 and G2
            var getInN1 = dstRG1[segRG1[n1]..<segRG1[n1+1]];
            var getInN2 = dstRG2[segRG2[n2]..<segRG2[n2+1]];

            // Check in neighbors of n2 
            for In2 in getInN2 {
                if state.isMappedn2(In2) {
                    //var In1 = state.core2(In2);
                    var In1 = state.core(In2);
                    var eid1 = getEdgeId(In1, n1, dstNodesG1, segGraphG1);
                    var eid2 = getEdgeId(In2, n2, dstNodesG2, segGraphG2);
                    
                    // var (flag1, label1) = getRelationships(segGraphG1, dstNodesG1, convertedRelationshipsG1, In1, n1);
                    // var (flag2, label2) = getRelationships(segGraphG2, dstNodesG2, convertedRelationshipsG2, In2, n2);

                    if eid1 == -1 || eid2 == -1 {
                        timerisFeasible.stop();
                        TimerArrNew[2] += timerisFeasible.elapsed();
                        return false;
                    }

                    // var label1 = convertedRelationshipsG1[eid1];
                    // var label2 = convertedRelationshipsG2[eid2];
                    var relationshipsG1eid1 = convertedRelationshipsG1[eid1];
                    var relationshipsG2eid2 = convertedRelationshipsG2[eid2];
                    //var intersection = relationshipsG1eid1 & relationshipsG2eid2;
            
                    // if intersection.size <= 0 {
                    if relationshipsG1eid1 != relationshipsG2eid2 {;
                        timerisFeasible.stop();
                        TimerArrNew[2] += timerisFeasible.elapsed();
                        return false;
                    }
                }
                else {
                    if state.Tin2.contains(In2) then termin2 += 1;
                    if state.Tout2.contains(In2) then termout2 += 1;
                    if !state.Tin2.contains(In2) && !state.Tout2.contains(In2) then new2 += 1;
                }
            }
            
            // Check out neighbors of n1 
            for Out1 in getOutN1 {
                if !state.isMappedn1(Out1) {
                    if state.Tin1.contains(Out1) then termin1 += 1;
                    if state.Tout1.contains(Out1) then termout1 += 1;
                    if !state.Tin1.contains(Out1) && !state.Tout1.contains(Out1) then new1 += 1;
                }
            }
            
            // Check in neighbors of n1 
            for In1 in getInN1 {
                if !state.isMappedn1(In1) {
                    if state.Tin1.contains(In1) then termin1 += 1;
                    if state.Tout1.contains(In1) then termout1 += 1;
                    if !state.Tin1.contains(In1) && !state.Tout1.contains(In1) then new1 += 1;
                }
            }
            timerisFeasible.stop();
            TimerArrNew[2] += timerisFeasible.elapsed();
            if !(termin2<=termin1 && termout2<=termout1 && (termin2+termout2+new2)<=(termin1+termout1+new1)) {
                return false;
            }


            ////Label check
            if !nodesLabelCompatible(n1, n2) {
                timerisFeasible.stop();
                TimerArrNew[2] += timerisFeasible.elapsed();
                return false;
            }

            return true;
        } // end of isFeasible

        /** Depth-first-search-like steps to traverse a graph and return a list of all solution 
        states.*/
        proc dfs(ref initialState: State, g1: SegGraph, g2: SegGraph) throws {

            var timerfirstpartdfs:stopwatch;
            timerfirstpartdfs.start();


            //var allmappings: list (set((int, int)));
            var allmappings: list([0..#g2.n_vertices] int);
            var stack:list(State, parSafe=true); // stack for backtracking
            



            
            stack.pushBack(initialState); // Initialize stack.
            
            timerfirstpartdfs.stop();
            TimerArrNew[10] += timerfirstpartdfs.elapsed();
            
            var timerwhile:stopwatch;
            timerwhile.start();

            while stack.size > 0 {
                
                var timerWhileIF:stopwatch;
                timerWhileIF.start();
                
                var state = stack.popBack();
                //if state.mapping.size == g2.n_vertices then allmappings.pushBack(state.mapping);
                if (min reduce state.core != -1 ){
                //if (state.depth == g2.n_vertices ){
                    allmappings.pushBack(state.core);
                    //writeln("current mapping # ", numIso," = ",state.core );
                    //numIso += 1;

                } 
                timerWhileIF.stop();
                TimerArrNew[22] += timerWhileIF.elapsed();
                
                //writeln("after adding allmappings is now = ", allmappings);
                //var candidatesOpti = getCandidatePairsOpti(state);
                var (candidatesOptiG1, candidatesOptiG2, flag) = getCandidatePairsOpti(state);

                if flag {    
                    //for (n1, n2) in candidatesOpti {
                    for i in 0..candidatesOptiG1.size-1 {
                        var n1 = candidatesOptiG1[i];
                        var n2 = candidatesOptiG2;

                        if isFeasible(state, n1, n2) {
                            var newState = state.copy();
                            var timeraddPair:stopwatch;
                            timeraddPair.start();
                            newState.addPair(n1, n2);
                            timeraddPair.stop();
                            TimerArrNew[18] += timeraddPair.elapsed();
                            
                            var timeraddToTinTout:stopwatch;
                            timeraddToTinTout.start();
                            //newState = addToTinTout(newState, n1, n2);
                            newState.addToTinTout(n1, n2);
                            timeraddToTinTout.stop();
                            TimerArrNew[17] += timeraddToTinTout.elapsed();
                            
                            var timerpush2:stopwatch;
                            timerpush2.start();
                            stack.pushBack(newState);
                            timerpush2.stop();
                            TimerArrNew[16] += timerpush2.elapsed();
                        }
                    }
                }
                //var timerreset:stopwatch;
                //timerreset.start();
                //state.reset();
                //timerreset.stop();
                //TimerArrNew[12] += timerreset.elapsed();
            }
            timerwhile.stop();
            TimerArrNew[19] += timerwhile.elapsed();


            return allmappings; // Isomappings
        }  // end of dfs


        /** Main procedure that invokes all of the vf2 steps using the graph data that is
        initialized by `runVF2`.*/
        proc vf2(g1: SegGraph, g2: SegGraph): [] int throws {
            var initial = createInitialState();
            
            var timerDFS:stopwatch;
            timerDFS.start();
            var solutions = dfs(initial, g1, g2);
            //writeln("solutions from DFS = ", solutions);
            timerDFS.stop();
            TimerArrNew[3] += timerDFS.elapsed();

            var subIsoArrToReturn: [0..(solutions.size*g2.n_vertices)-1](int);
            //writlen("solutions = ",solutions );
            var timersolution:stopwatch;
            timersolution.start();

            var posOffset = 0;
            for solSet in solutions {
                //writeln("solSet = ", solSet);
                var indx = 0;
                for elem in solSet {
                    subIsoArrToReturn[posOffset + indx] = elem;
                    indx +=1;
                    //writeln(elem," add to subIsoArrToReturn");
                }
                posOffset += g2.n_vertices;
            }
            timersolution.stop();
            TimerArrNew[20] += timersolution.elapsed();
            return(subIsoArrToReturn);
        } //end of vf2
        
        writeln("\n\n\n\n\n");
        for i in 0..30 {
            if i == 0 then writeln("Preprocessing total time = ", TimerArrNew[0]);
            if i == 1 then writeln("VF2 total time = ", TimerArrNew[1]);        
            if i == 2 then writeln("isFeasible total time = ", TimerArrNew[2]);
            if i == 3 then writeln("DFS total time = ", TimerArrNew[3]);
            if i == 4 then writeln("nodesLabelCompatible total time = ", TimerArrNew[4]);
            if i == 5 then writeln("getUnmappedNodes total time = ", TimerArrNew[5]);
            if i == 6 then writeln("nodesLabelCompatible total time = ", TimerArrNew[6]);
            if i == 7 then writeln("getCandidatePairsOpti total time = ", TimerArrNew[7]);
            //writeln("\n\n***********Inside DFS which took = ", TimerArrNew[3]);
            if i == 10 then writeln("First part of DFS time = ", TimerArrNew[10]);
            //writeln("***************** inside while");
            if i == 16 then writeln("stack push 2 total time = ", TimerArrNew[16]);
            if i == 17 then writeln("addToTinTout total time = ", TimerArrNew[17]);
            if i == 18 then writeln("addPair total time = ", TimerArrNew[18]);
            if i == 19 then writeln("while total time = ", TimerArrNew[19]);
            if i == 20 then writeln("solution preparation total time = ", TimerArrNew[20]);
            if i == 21 then writeln("\n\naddToTinTout from inside time = ", TimerArrNew[21]);
            if i == 22 then writeln("\n Timer While if = ", TimerArrNew[22]);

/*
            if i == 13 then writeln("Tin Tout N1 remove time = ", TimerArrNew[13]);
            if i == 14 then writeln("for over in-nei N1 time = ", TimerArrNew[14]);
            if i == 15 then writeln("for over out-nei N1 time = ", TimerArrNew[15]);
            if i == 16 then writeln("\n\n IN-OUT neighbor G2 time = ", TimerArrNew[16]);
            if i == 19 then writeln("while outside = ", TimerArrNew[19]);
*/
        }
        writeln("\n\n\n\n\n");
        return IsoArr;
    } //end of runVF2
} // end of SubgraphIsomorphism module