import chalk_common, posix
export chalk_common

var
  ctxStack            = seq[CollectionCtx](@[])
  collectionCtx       = CollectionCtx()

# This is for when we're doing a `conf load`.  We force silence, turning off
# all logging of merit.
proc startTestRun*() =
  doingTestRun = true
proc endTestRun*()   =
  doingTestRun = false

proc pushCollectionCtx*(): CollectionCtx =
  ctxStack.add(collectionCtx)
  collectionCtx = CollectionCtx()
  result        = collectionCtx

proc popCollectionCtx*() =
  if len(ctxStack) != 0: collectionCtx = ctxStack.pop()

proc inSubscan*(): bool =
  return len(ctxStack) != 0
proc getCurrentCollectionCtx*(): CollectionCtx = collectionCtx
proc getErrorObject*(): Option[ChalkObj] = collectionCtx.currentErrorObject
proc setErrorObject*(o: ChalkObj) =
  collectionCtx.currentErrorObject = some(o)
proc clearErrorObject*() =
  collectionCtx.currentErrorObject = none(ChalkObj)
proc getAllChalks*(): seq[ChalkObj] = collectionCtx.allChalks
proc getAllChalks*(cc: CollectionCtx): seq[ChalkObj] = cc.allChalks
proc addToAllChalks*(o: ChalkObj) =
  collectionCtx.allChalks.add(o)
proc setAllChalks*(s: seq[ChalkObj]) =
  collectionCtx.allChalks = s
proc removeFromAllChalks*(o: ChalkObj) =
  if o in collectionCtx.allChalks:
    collectionCtx.allChalks.del(collectionCtx.allChalks.find(o))
proc getUnmarked*(): seq[string] = collectionCtx.unmarked
proc addUnmarked*(s: string) =
  collectionCtx.unmarked.add(s)
proc isMarked*(chalk: ChalkObj): bool {.inline.} = return chalk.marked
proc newChalk*(name:         string            = "",
               pid:          Option[Pid]       = none(Pid),
               fsRef:        string            = "",
               tag:          string            = "",
               imageId:      string            = "",
               containerId:  string            = "",
               marked:       bool              = false,
               stream:       FileStream        = FileStream(nil),
               resourceType: set[ResourceType] = {ResourceFile},
               extract:      ChalkDict         = ChalkDict(nil),
               cache:        RootRef           = RootRef(nil),
               codec:        Codec             = Codec(nil)): ChalkObj =
  result = ChalkObj(name:          name,
                    pid:           pid,
                    fsRef:         fsRef,
                    stream:        stream,
                    tagRef:        tag,
                    marked:        marked,
                    imageId:       imageId,
                    containerId:   containerId,
                    collectedData: ChalkDict(),
                    opFailed:      false,
                    resourceType:  resourceType,
                    extract:       extract,
                    cache:         cache,
                    myCodec:       codec)
  setErrorObject(result)

template setIfNotEmpty*(dict: ChalkDict, key: string, val: string) =
  if val != "":
    dict[key] = pack(val)

template setIfNotEmpty*[T](dict: ChalkDict, key: string, val: seq[T]) =
  if len(val) > 0:
    dict[key] = pack[seq[T]](val)

proc idFormat*(rawHash: string): string =
  let s = base32vEncode(rawHash)
  s[0 ..< 6] & "-" & s[6 ..< 10] & "-" & s[10 ..< 14] & "-" & s[14 ..< 20]

template hashFmt*(s: string): string =
  s.toHex().toLowerAscii()

template isSubscribedKey*(key: string): bool =
  if key in subscribedKeys:
    subscribedKeys[key]
  else:
    false

template setIfSubscribed[T](d: ChalkDict, k: string, v: T) =
  if isSubscribedKey(k):
    d[k] = pack[T](v)

template setIfNeeded*[T](o: ChalkDict, k: string, v: T) =
  when T is string:
    if v != "":
      setIfSubscribed(o, k, v)
  elif T is seq or T is ChalkDict:
    if len(v) != 0:
      setIfSubscribed(o, k, v)
  else:
    setIfSubscribed(o, k, v)

template setIfNeeded*[T](o: ChalkObj, k: string, v: T) =
  setIfNeeded(o.collectedData, k, v)

proc isChalkingOp*(): bool =
  return commandName in chalkConfig.getValidChalkCommandNames()

proc lookupCollectedKey*(obj: ChalkObj, k: string): Option[Box] =
  if k in hostInfo:          return some(hostInfo[k])
  if k in obj.collectedData: return some(obj.collectedData[k])
  return none(Box)

var args: seq[string]

proc setArgs*(a: seq[string]) =
  args = a
proc getArgs*(): seq[string] = args

var cmdSpec*: CommandSpec = nil
proc getArgCmdSpec*(): CommandSpec = cmdSpec

var contextDirectories: seq[string]

template setContextDirectories*(l: seq[string]) =
  # Used for 'where to look for stuff' plugins, particularly version control.
  contextDirectories = l

template getContextDirectories*(): seq[string] =
  contextDirectories

var hostCollectionSuspends = 0
template suspendHostCollection*() =         hostCollectionSuspends += 1
template restoreHostCollection*() =         hostCollectionSuspends -= 1
template hostCollectionSuspended*(): bool = hostCollectionSuspends != 0
