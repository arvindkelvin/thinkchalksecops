import osproc, config, util

var
  buildXVersion:     float  = 0   # Major and minor only

const
  hashHeader* = "sha256:"


var dockerPathOpt: Option[string] = none(string)


template extractDockerHash*(value: string): string =
  if not value.startsWith(hashHeader):
    value
  else:
    value[len(hashHeader) .. ^1]

template extractBoxedDockerHash*(value: Box): Box =
  pack(extractDockerHash(unpack[string](value)))

proc setDockerExeLocation*() =
  once:
    trace("Searching path for 'docker'")
    var
      userPath: seq[string]
      exeOpt   = chalkConfig.getDockerExe()

    if exeOpt.isSome():
      userPath.add(exeOpt.get())

    dockerPathOpt     = findExePath("docker", userPath, ignoreChalkExes = true)
    dockerExeLocation = dockerPathOpt.get("")

    if dockerExeLocation == "":
       warn("No docker command found in path. `chalk docker` not available.")

proc getBuildXVersion*(): float =
  # Have to parse the thing to get compares right.
  once:
    if getEnv("DOCKER_BUILDKIT") == "0":
      return 0
    let (output, exitcode) = execCmdEx(dockerExeLocation & " buildx version")
    if exitcode == 0:
      let parts = output.split(' ')
      if len(parts) >= 2 and len(parts[1]) > 1 and parts[1][0] == 'v':
        let vparts = parts[1][1 .. ^1].split('.')
        if len(vparts) > 1:
          let majorMinorStr = vparts[0] & "." & vparts[1]
          try:
            buildXVersion = parseFloat(majorMinorStr)
          except:
            dumpExOnDebug()

  return buildXVersion

template haveBuildContextFlag*(): bool =
  buildXVersion >= 0.8

proc runDockerGetOutput*(args: seq[string]): string =
  trace("Running: " & dockerExeLocation & " " & args.join(" "))
  return runCmdGetOutput(dockerExeLocation, args = args)

template runDockerGetEverything*(args: seq[string]): ExecOutput =
  runCmdGetEverything(dockerExeLocation, args)

var contextCounter = 0

proc makeFileAvailableToDocker*(ctx:      DockerInvocation,
                                loc:      string,
                                move:     bool,
                                newName = "") =
  let (dir, file) = loc.splitPath()

  if haveBuildContextFlag():
    once:
      trace("Docker injection method: --build-context")

    ctx.newCmdLine.add("--build-context")
    ctx.newCmdLine.add("chalktmpdir" & $(contextCounter) & "=\"" & dir & "\"")
    ctx.addedInstructions.add("COPY --from=chalkexedir" & $(contextCounter) &
      " " & file & " /" & newname)
    contextCounter += 1
    if move:
      registerTempFile(loc)
  elif ctx.foundContext == "-":
    warn("Cannot chalk when context is passed to stdin w/o BUILDKIT support")
    raise newException(ValueError, "stdinctx")
  else:
    let
      contextDir  = resolvePath(ctx.foundContext)
      dstLoc      = contextDir.joinPath(file)

    if not dirExists(contextDir):
      warn("Cannot find context directory (" & contextDir &
        "), so cannot wrap entry point.")
      raise newException(ValueError, "ctxwrite")
    if fileExists(dstLoc):
      # This shouldn't happen w/ the chalk mark, as the file name is randomized
      # but it could happen w/ the chalk exe
      warn("File name: '" & file & "already exists in the context. Assuming " &
        "this is the file to copy in.")
      return
    else:
      try:
        if move:
          moveFile(loc, dstLoc)
        else:
          copyFile(loc, dstLoc)

        ctx.addedInstructions.add("COPY " & file & " " & " /" & newname)
        registerTempFile(dstLoc)
      except:
        dumpExOnDebug()
        warn("Could not write to context directory.")
        raise newException(ValueError, "ctxcpy")

proc chooseNewTag*(): string =
  let
    randInt = secureRand[uint]()
    hexVal  = toHex(randInt and 0xffffffffffff'u).toLowerAscii()

  return "chalk-" & hexVal & ":latest"

proc getAllDockerContexts*(info: DockerInvocation): seq[string] =
  if info.foundContext != "" and info.foundContext != "-":
    result.add(resolvePath(info.foundContext))

  for k, v in info.otherContexts:
    result.add(resolvePath(v))

proc populateBasicImageInfo*(chalk: ChalkObj, info: JSonNode) =
  let
    repo  = info["Repository"].getStr()
    tag   = info["Tag"].getStr.replace("\u003cnone\u003e", "").strip()
    short = info["ID"].getStr()

  chalk.repo    = repo
  chalk.tag     = tag
  chalk.shortId = short

proc getBasicImageInfo*(refName: string): Option[JSonNode] =
  let
    allInfo = runDockerGetEverything(@["images", refName, "--format", "json"])
    stdout  = allInfo.getStdout().strip()

  if allInfo.getExit() != 0 or stdout == "":
    return none(JsonNode)

  let lines = stdout.split("\n")

  if len(lines) < 1:
    return none(JsonNode)

  return some(parseJson(lines[0]))

proc extractBasicImageInfo*(chalk: ChalkObj): bool =
  # usreRef should always be what was passed on the command line, and
  # if nothing was passed on the command line, it will be our
  # temporary tag.
  let info = getBasicImageInfo(chalk.userRef)

  if info.isNone():
    return false

  chalk.populateBasicImageInfo(info.get())
  return true