module SubgraphSearchMsg {
  // Chapel modules.
  use Reflection;
  use Map;
  use Time;
  
  // Arachne modules.
  use GraphArray;
  use SubgraphSearch; 
  
  // Arkouda modules.
  use MultiTypeSymbolTable;
  use MultiTypeSymEntry;
  use ServerConfig;
  use ServerErrors;
  use ServerErrorStrings;
  use AryUtil;
  use Logging;
  use Message;
  
  // Server message logger. 
  private config const logLevel = ServerConfig.logLevel;
  private config const logChannel = ServerConfig.logChannel;
  const siLogger = new Logger(logLevel, logChannel);

  /**
  Parses message from Python and invokes the kernel to find subgraphs from G that are isomorphic
  to H.
  
  :arg cmd: operation to perform. 
  :type cmd: string
  :arg msgArgs: arguments passed to backend. 
  :type msgArgs: borrowed MessageArgs
  :arg st: symbol table used for storage.
  :type st: borrowed SymTab
  
  :returns: MsgTuple
  */
  proc subgraphSearchMsg(cmd: string, msgArgs: borrowed MessageArgs, st: borrowed SymTab): MsgTuple throws {
    param pn = Reflection.getRoutineName();
    var repMsg, outMsg:string;

    // Extract messages sent from Python.
    var graphEntryName = msgArgs.getValueOf("MainGraphName");
    var subgraphEntryName = msgArgs.getValueOf("SubGraphName");
    var sizeLimit = msgArgs.getValueOf("SizeLimit");
    var timeLimit = msgArgs.getValueOf("TimeLimit");
    var returnIsosAs = msgArgs.getValueOf("ReturnIsosAs");
    var reorderType = msgArgs.getValueOf("ReorderType");
    var algorithmType = msgArgs.getValueOf("AlgorithmType");
    var matchType = msgArgs.getValueOf("MatchType");
    var printProgressInterval = msgArgs.getValueOf("PrintProgressInterval");
     
    // Pull out our graph from the symbol table.
    var gEntry: borrowed GraphSymEntry = getGraphSymEntry(graphEntryName, st); 
    var g = gEntry.graph;

    // Pull out our subgraph from the symbol table.
    var hEntry: borrowed GraphSymEntry = getGraphSymEntry(subgraphEntryName, st); 
    var h = hEntry.graph;

    var timer:stopwatch;
    if g.isDirected() {
      if algorithmType != "ps" && algorithmType != "si" {
        var errorMsg = notImplementedError(pn, "unknown algorithm type");
        siLogger.error(getModuleName(), getRoutineName(), getLineNumber(), errorMsg);
        return new MsgTuple(errorMsg, MsgType.ERROR);
      }

      timer.start();
      var isos = runSearch(g,h,returnIsosAs,sizeLimit,timeLimit,printProgressInterval,algorithmType,
                           reorderType,matchType,st);
      timer.stop();
      outMsg = "runSearch took %r sec".format(timer.elapsed());
      siLogger.info(getModuleName(),getRoutineName(),getLineNumber(),outMsg);

      if returnIsosAs == "vertices" {
        var isosAsVerticesName = st.nextName();
        var isosAsVerticesEntry = createSymEntry(isos[0]);
        st.addEntry(isosAsVerticesName, isosAsVerticesEntry);
        
        var isosAsVerticesMapperName = st.nextName();
        var isosAsVerticesMapperEntry = createSymEntry(isos[1]);
        st.addEntry(isosAsVerticesMapperName, isosAsVerticesMapperEntry);
        
        repMsg = "created " + st.attrib(isosAsVerticesName)
               + "+ created " + st.attrib(isosAsVerticesMapperName);
      } else if returnIsosAs == "edges" {
        var isosAsEdgesSrcName = st.nextName();
        var isosAsEdgesSrcEntry = createSymEntry(isos[0]);
        st.addEntry(isosAsEdgesSrcName, isosAsEdgesSrcEntry);

        var isosAsEdgesDstName = st.nextName();
        var isosAsEdgesDstEntry = createSymEntry(isos[1]);
        st.addEntry(isosAsEdgesDstName, isosAsEdgesDstEntry);
        
        repMsg = "created " + st.attrib(isosAsEdgesSrcName) 
               + "+ created " + st.attrib(isosAsEdgesDstName);
      } else if returnIsosAs == "complete" {
        var isosAsVerticesName = st.nextName();
        var isosAsVerticesEntry = createSymEntry(isos[0]);
        st.addEntry(isosAsVerticesName, isosAsVerticesEntry);
        
        var isosAsVerticesMapperName = st.nextName();
        var isosAsVerticesMapperEntry = createSymEntry(isos[1]);
        st.addEntry(isosAsVerticesMapperName, isosAsVerticesMapperEntry);
        
        var isosAsEdgesSrcName = st.nextName();
        var isosAsEdgesSrcEntry = createSymEntry(isos[2]);
        st.addEntry(isosAsEdgesSrcName, isosAsEdgesSrcEntry);

        var isosAsEdgesDstName = st.nextName();
        var isosAsEdgesDstEntry = createSymEntry(isos[3]);
        st.addEntry(isosAsEdgesDstName, isosAsEdgesDstEntry);
        
        repMsg = "created " + st.attrib(isosAsVerticesName)
               + "+ created " + st.attrib(isosAsVerticesMapperName)
               + "+ created " + st.attrib(isosAsEdgesSrcName)
               + "+ created " + st.attrib(isosAsEdgesDstName);
      } else if returnIsosAs == "count" {
        var count = isos[0][0];
        repMsg = count:string;
      } else {
        var errorMsg = notImplementedError(pn, "return_isos_as == %s".format(returnIsosAs));
        siLogger.error(getModuleName(), getRoutineName(), getLineNumber(), errorMsg);
        return new MsgTuple(errorMsg, MsgType.ERROR);
      }
      siLogger.info(getModuleName(),getRoutineName(),getLineNumber(),repMsg);

      return new MsgTuple(repMsg, MsgType.NORMAL);
    } else {
      var errorMsg = notImplementedError(pn, "subgraph %s for undirected graphs".format(matchType));
      siLogger.error(getModuleName(), getRoutineName(), getLineNumber(), errorMsg);
      return new MsgTuple(errorMsg, MsgType.ERROR);
    }
  } // end of subgraphSearchMsg

  use CommandMap;
  registerFunction("subgraphSearch", subgraphSearchMsg, getModuleName());
} // end of module