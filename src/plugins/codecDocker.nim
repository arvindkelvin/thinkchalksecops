## :Author: John Viega, Brandon Edwards
## :Copyright: 2023, Crash Override, Inc.

import osproc,  glob, std/tempfiles, ../config, ../docker_base, ../chalkjson

type
  CodecDocker* = ref object of Codec

method keepScanningOnSuccess*(self: CodecDocker): bool = true

method getChalkId*(self: CodecDocker, chalk: ChalkObj): string =
  if chalk.extract != nil and "CHALK_ID" in chalk.extract:
    return unpack[string](chalk.extract["CHALK_ID"])
  var
    b      = secureRand[array[32, char]]()
    preRes = newStringOfCap(32)
  for ch in b: preRes.add(ch)
  return preRes.idFormat()


template extractFinish() =
  setCurrentDir(cwd)
  try:
    removeDir(dir)
  except:
    dumpExOnDebug()
  return

proc extractImageMark(imageId: string, loc: string, chalk: ChalkObj) =
  # Need to integrate Theo's attestation bits here, but here's the
  # fallback option.  For now, if a manifest is a multi-arch image, we
  # still just look at the first item, rather than treating each as
  # a separate image.
  let
    cwd  = getCurrentDir()
    dir  = createTempDir("docker_image_", "_extract")

  try:
    setCurrentDir(dir)

    if runDocker(@["save", imageId, "-o", "image.tar"]) != 0:
      error("Image " & imageId & ": error extracting chalk mark")
      extractFinish()
    if execCmd("tar -xf image.tar manifest.json") != 0:
      error("Image " & imageId & ": could not extract manifest (no tar cmd?)")
      extractFinish()

    let
      file   = newFileStream("manifest.json")

    if file == nil:
      error("Image " & imageId & ": could not extract manifest (permissions?)")
      extractFinish()
    let
      str    = file.readAll()
      json   = str.parseJson()
      layers = json.getElems()[0]["Layers"]

    file.close()

    if execCmd("tar -xf image.tar " & layers[^1].getStr()) != 0:
      error("Image " & imageId & ": error extracting chalk mark")
      extractFinish()

    if execCmd("tar -xf " & layers[^1].getStr() &
      " chalk.json 2>/dev/null") == 0:
      let file = newFileStream("chalk.json")

      if file == nil:
        error("Image " & imageId & " has a chalk file but we can't read it?")
        extractFinish()
      chalk.extract = extractOneChalkJson(file, imageId)
      chalk.marked  = true
      file.close()
      trace("Image " & imageId & ": chalk mark extracted")
      extractFinish()

    else:
      warn("Image " & imageId & " has no chalk mark in the top layer.")
      if not chalkConfig.extractConfig.getSearchBaseLayersForMarks():
        extractFinish()
      # We're only going to go deeper if there's no chalk mark found.
      var
        n = len(layers) - 1

      while n != 0:
        n = n - 1
        if execCmd("tar -xf " & layers[n].getStr() &
          " chalk.json 2>/dev/null") == 0:
          let file = newFileStream("chalk.json")
          if file == nil:
            continue
          try:
            let
              extract = extractOneChalkJson(file, imageId)
              cid     = extract["CHALK_ID"]
              mdid    = extract["METADATA_ID"]

            info("In layer " & $(n) & " (of " & $(len(layers)) & "), found " &
              "Chalk mark reporting CHALK_ID = " & $(cid) &
              " and METADATA_ID = " & $(mdid))
            chalk.collectedData["_FOUND_BASE_MARK"] = pack(@[cid, mdid])
            extractFinish()
          except:
            continue
      extractFinish()
  except:
    dumpExOnDebug()
    trace(imageId & ": Could not complete mark extraction")
    extractFinish()

proc extractContainerMark(cid: string, loc: string, chalk: ChalkObj) =
  try:
    let rawmark = runDockerGetOutput(@["cp", cid & ":" & loc, "-"])

    if rawmark.contains("No such container"):
      error("Container " & cid & " shut down before mark extraction")
    elif rawmark.contains("Cout not find the file"):
      warn("Container " & cid & " is unmarked.")
    else:
      chalk.extract = extractOneChalkJson(newStringStream(rawmark), cid)
      chalk.marked  = true
      trace("Container " & cid & ": chalk mark extracted")
  except:
    dumpExOnDebug()
    error("Got error when extracting from container " & cid)

method scanArtifactLocations*(codec:      CodecDocker,
                              exclusions: var seq[string],
                              ignoreList: seq[glob.Glob],
                              recurse:    bool) : seq[ChalkObj] =

  if getCommandName() != "extract":
    return

  let
    do_images      = chalkConfig.extractConfig.getExtractFromImages()
    do_containers  = chalkConfig.extractConfig.getExtractFromContainers()
    markLocation   = chalkConfig.dockerConfig.getChalkFileLocation()
    reportUnmarked = chalkConfig.dockerConfig.getReportUnmarked()

  if not do_images and not do_containers:
    return

  if do_images:
    try:
      let raw = runDockerGetOutput(@["images", "--format", "json"]).strip()

      if raw == "":
        trace("No local images.")
      else:
        for line in raw.split("\n"):
          let
            imageId = parseJson(line)["ID"].getStr()
            chalk   = newChalk(name         = "image:" & imageId,
                               codec        = codec,
                               imageId      = imageId,
                               extract      = ChalkDict(),
                               resourceType = {ResourceImage})

          if not isChalkingOp():
            extractImageMark(chalk.imageId, markLocation, chalk)

          result.add(chalk)
    except:
      dumpExOnDebug()
      trace("No docker command found.")
      return

  if do_containers:
    try:
      let raw = runDockerGetOutput(@["ps", "--format", "json"]).strip()

      if raw == "":
        trace("No running containers.")
        return
      for line in raw.split("\n"):
        let
          containerId = parseJson(line)["Id"].getStr()
          chalk       = newChalk(name         = "container:" & containerId,
                                 containerId  = containerId,
                                 codec        = codec,
                                 resourceType = {ResourceContainer})

        if not isChalkingOp():
          extractContainerMark(chalk.containerId, markLocation, chalk)

        result.add(chalk)
    except:
      dumpExOnDebug()
      trace("Could not run docker.")

# These are the keys we can auto-convert without any special-casing.
# Types of the JSon will be checked against the key's declared type.
let dockerImageAutoMap = {
  "RepoTags":                           "_REPO_TAGS",
  "RepoDigests":                        "_REPO_DIGESTS",
  "Comment":                            "_IMAGE_COMMENT",
  "Created":                            "_IMAGE_CREATION_DATETIME",
  "DockerVersion":                      "_IMAGE_DOCKER_VERSION",
  "Author":                             "_IMAGE_AUTHOR",
  "Architecture":                       "_IMAGE_ARCHITECTURE",
  "Variant":                            "_IMAGE_VARIANT",
  "OS":                                 "_IMAGE_OS",
  "OsVersion":                          "_IMAGE_OS_VERSION",
  "Size":                               "_IMAGE_SIZE",
  "RootFS.Type":                        "_IMAGE_ROOT_FS_TYPE",
  "RootFS.Layers",                      "_IMAGE_ROOT_FS_LAYERS",
  "Config.Hostname":                    "_IMAGE_HOSTNAMES",
  "Config.Domainname":                  "_IMAGE_DOMAINNAME",
  "Config.User":                        "_IMAGE_USER",
  "Config.ExposedPorts":                "_IMAGE_EXPOSEDPORTS",
  "Config.Env":                         "_IMAGE_ENV",
  "Config.Cmd":                         "_IMAGE_CMD",
  "Config.Image":                       "_IMAGE_NAME",
  "Config.Healthcheck.Test":            "_IMAGE_HEALTHCHECK_TEST",
  "Config.Healthcheck.Interval":        "_IMAGE_HEALTHCHECK_INTERVAL",
  "Config.Healthcheck.Timeout":         "_IMAGE_HEALTHCHECK_TIMEOUT",
  "Config.Healthcheck.StartPeriod":     "_IMAGE_HEALTHCHECK_START_PERIOD",
  "Config.Healthcheck.StartInterval":   "_IMAGE_HEALTHCHECK_START_INTERVAL",
  "Config.Healthcheck.Retries":         "_IMAGE_HEALTHCHECK_RETRIES",
  "Config.Volumes":                     "_IMAGE_MOUNTS",
  "Config.WorkingDir":                  "_IMAGE_WORKINGDIR",
  "Config.Entrypoint":                  "_IMAGE_ENTRYPOINT",
  "Config.NetworkDisabled":             "_IMAGE_NETWORK_DISABLED",
  "Config.MacAddress":                  "_IMAGE_MAC_ADDR",
  "Config.OnBuild":                     "_IMAGE_ONBUILD",
  "Config.Labels":                      "_IMAGE_LABELS",
  "Config.StopSignal":                  "_IMAGE_STOP_SIGNAL",
  "Config.StopTimeout":                 "_IMAGE_STOP_TIMEOUT",
  "Config.Shell":                       "_IMAGE_SHELL",
  "VirtualSize":                        "_IMAGE_VIRTUAL_SIZE",
  "Metadata.LastTagTime":               "_IMAGE_LAST_TAG_TIME",
  "GraphDriver":                        "_IMAGE_STORAGE_METADATA"
  }.toOrderedTable()

let dockerContainerAutoMap = {
  "Id":                                 "_INSTANCE_CONTAINER_ID",
  "Created":                            "_INSTANCE_CREATION_DATETIME",
  "Path":                               "_INSTANCE_ENTRYPOINT_PATH",
  "Args":                               "_INSTANCE_ENTRYPOINT_ARGS",
  "State.Status":                       "_INSTANCE_STATUS",
  "State.Pid":                          "_INSTANCE_PID",
  "ResolvConfPath":                     "_INSTANCE_RESOLVE_CONF_PATH",
  "HostNamePath":                       "_INSTANCE_HOSTNAME_PATH",
  "HostsPath":                          "_INSTANCE_HOSTS_PATH",
  "LogPath":                            "_INSTANCE_LOG_PATH",
  "Name":                               "_INSTANCE_NAME",
  "RestartCount":                       "_INSTANCE_RESTART_COUNT",
  "Driver":                             "_INSTANCE_DRIVER",
  "Platform":                           "_INSTANCE_PLATFORM",
  "MountLabel":                         "_INSTANCE_MOUNT_LABEL",
  "ProcessLabel":                       "_INSTANCE_PROCESS_LABEL",
  "AppArmorProfile":                    "_INSTANCE_APP_ARMOR_PROFILE",
  "ExecIDs":                            "_INSTANCE_EXEC_IDS",
  "HostConfig.Binds":                   "_INSTANCE_BINDS",
  "HostConfig.ContainerIDFile":         "_INSTANCE_CONTAINER_ID_FILE",
  "HostConfig.LogConfig.Config":        "_INSTANCE_LOG_CONFIG",
  "HostConfig.NetworkMode":             "_INSTANCE_NETWORK_MODE",
  "HostConfig.PortBindings":            "_INSTANCE_BOUND_PORTS",
  "HostConfig.RestartPolicy.Name":      "_INSTANCE_RESTART_POLICY_NAME",
  "HostConfig.RestartPolicy.MaximumRetryCount": "_INSTANCE_RESTART_RETRY_COUNT",
  "HostConfig.AutoRemove":              "_INSTANCE_AUTOREMOVE",
  "HostConfig.VolumeDriver":            "_INSTANCE_VOLUME_DRIVER",
  "HostConfig.VolumesFrom":             "_INSTANCE_VOLUMES_FROM",
  "HostConfig.ConsoleSize":             "_INSTANCE_CONSOLE_SIZE",
  "HostConfig.CapAdd":                  "_INSTANCE_ADDED_CAPS",
  "HostConfig.CapDrop":                 "_INSTANCE_DROPPED_CAPS",
  "HostConfig.CgroupnsMode":            "_INSTANCE_CGROUP_NS_MODE",
  "HostConfig.Dns":                     "_INSTANCE_DNS",
  "HostConfig.DnsOptions":              "_INSTANCE_DNS_OPTIONS",
  "HostConfig.DnsSearch":               "_INSTANCE_DNS_SEARCH",
  "HostConfig.ExtraHosts":              "_INSTANCE_EXTRA_HOSTS",
  "HostConfig.GroupAdd":                "_INSTANCE_GROUP_ADD",
  "HostConfig.IpcMode":                 "_INSTANCE_IPC_MODE",
  "HostConfig.Cgroup":                  "_INSTANCE_CGROUP",
  "HostConfig.Links":                   "_INSTANCE_LINKS",
  "HostConfig.OomScoreAdj":             "_INSTANCE_OOM_SCORE_ADJ",
  "HostConfig.PidMode":                 "_INSTANCE_PID_MODE",
  "HostConfig.Privileged":              "_INSTANCE_IS_PRIVILEGED",
  "HostConfig.PublishAllPorts":         "_INSTANCE_PUBLISH_ALL_PORTS",
  "HostConfig.ReadonlyRootfs":          "_INSTANCE_READONLY_ROOT_FS",
  "HostConfig.SecurityOpt":             "_INSTANCE_SECURITY_OPT",
  "HostConfig.UTSMode":                 "_INSTANCE_UTS_MODE",
  "HostConfig.UsernsMode":              "_INSTANCE_USER_NS_MODE",
  "HostConfig.ShmSize":                 "_INSTANCE_SHM_SIZE",
  "HostConfig.Runtime":                 "_INSTANCE_RUNTIME",
  "HostConfig.Isolation":               "_INSTANCE_ISOLATION",
  "HostConfig.CpuShares":               "_INSTANCE_CPU_SHARES",
  "HostConfig.Memory":                  "_INSTANCE_MEMORY",
  "HostConfig.NanoCpus":                "_INSTANCE_NANO_CPUS",
  "HostConfig.CgroupParent":            "_INSTANCE_CGROUP_PARENT",
  "HostConfig.BlkioWeight":             "_INSTANCE_BLOCKIO_WEIGHT",
  "HostConfig.BlkioWeightDevice":       "_INSTANCE_BLOCKIO_WEIGHT_DEVICE",
  "HostConfig.BlkioDeviceReadBps":      "_INSTANCE_BLOCKIO_DEVICE_READ_BPS",
  "HostConfig.BlkioDeviceWriteBps":     "_INSTANCE_BLOCKIO_DEVICE_WRITE_BPS",
  "HostConfig.BlkioDeviceReadIOps":     "_INSTANCE_BLOCKIO_DEVICE_READ_IOPS",
  "HostConfig.BlkioDeviceWriteIops":    "_INSTANCE_BLOCKIO_DEVICE_WRITE_IOPS",
  "HostConfig.CpuPeriod":               "_INSTANCE_CPU_PERIOD",
  "HostConfig.CpuQuota":                "_INSTANCE_CPU_QUOTA",
  "HostConfig.CpuRealtimePeriod":       "_INSTANCE_CPU_REALTIME_PERIOD",
  "HostConfig.CpuRealtimeRuntime":      "_INSTANCE_CPU_REALTIME_RUNTIME",
  "HostConfig.CpusetCpus":              "_INSTANCE_CPUSET_CPUS",
  "HostConfig.CpusetMems":              "_INSTANCE_CPUSET_MEMS",
  "HostConfig.Devices":                 "_INSTANCE_DEVICES",
  "HostConfig.DeviceCgroupRules":       "_INSTANCE_CGROUP_RULES",
  "HostConfig.DeviceRequests":          "_INSTANCE_DEVICE_REQUESTS",
  "HostConfig.MemoryReservation":       "_INSTANCE_MEMORY_RESERVATION",
  "HostConfig.MemorySwap":              "_INSTANCE_MEMORY_SWAP",
  "HostConfig.MemorySwappiness":        "_INSTANCE_MEMORY_SWAPPINESS",
  "HostConfig.OomKillDisable":          "_INSTANCE_OOM_KILL_DISABLE",
  "HostConfig.PidsLimit":               "_INSTANCE_PIDS_LIMIT",
  "HostConfig.Ulimits":                 "_INSTANCE_ULIMITS",
  "HostConfig.CpuCount":                "_INSTANCE_CPU_COUNT",
  "HostConfig.CpuPercent":              "_INSTANCE_CPU_PERCENT",
  "HostConfig.IOMaximumIOps":           "_INSTANCE_IO_MAX_IOPS",
  "HostConfig.IOMaximumBandwidth":      "_INSTANCE_IO_MAX_BPS",
  "HostConfig.MaskedPaths":             "_INSTANCE_MASKED_PATHS",
  "HostConfig.ReadonlyPaths":           "_INSTANCE_READONLY_PATHS",
  "GraphDriver":                        "_INSTANCE_STORAGE_METADATA",
  "Mounts":                             "_INSTANCE_MOUNTS",
  "Config.Hostname":                    "_INSTANCE_HOSTNAMES",
  "Config.Domainname":                  "_INSTANCE_DOMAINNAME",
  "Config.User":                        "_INSTANCE_USER",
  "Config.AttachStdin":                 "_INSTANCE_ATTACH_STDIN",
  "Config.AttachStdout":                "_INSTANCE_ATTACH_STDOUT",
  "Config.AttachStderr":                "_INSTANCE_ATTACH_STDERR",
  "Config.ExposedPorts":                "_INSTANCE_EXPOSED_PORTS",
  "Config.Tty":                         "_INSTANCE_HAS_TTY",
  "Config.OpenStdin":                   "_INSTANCE_OPEN_STDIN",
  "Config.StdinOnce":                   "_INSTANCE_STDIN_ONCE",
  "Config.Env":                         "_INSTANCE_ENV",
  "Config.Cmd":                         "_INSTANCE_CMD",
  "Config.Image":                       "_INSTANCE_CONFIG_IMAGE",
  "Config.Volumes":                     "_INSTANCE_VOLUMES",
  "Config.WorkingDir":                  "_INSTANCE_WORKING_DIR",
  "Config.Entrypoint":                  "_INSTANCE_ENTRYPOINT",
  "Config.OnBuild":                     "_INSTANCE_ONBUILD",
  "Config.Labels":                      "_INSTANCE_LABELS",
  "NetworkSettings.Bridge":             "_INSTANCE_BRIDGE",
  "NetworkSettings.SandboxId":          "_INSTANCE_SANDBOXID",
  "NetworkSettings.HairpinMode":        "_INSTANCE_HAIRPINMODE",
  "NetworkSettings.LinkLocalIPv6Address":   "_INSTANCE_LOCAL_IPV6",
  "NetworkSettings.LinkLocalIPv6PrefixLen": "_INSTANCE_LOCAL_IPV6_PREFIX_LEN",
  "NetworkSettings.Ports":                  "_INSTANCE_BOUND_PORTS",
  "NetworkSettings.SanboxKey":              "_INSTANCE_SANDBOX_KEY",
  "NetworkSettings.SecondaryIPAddresses":   "_INSTANCE_SECONDARY_IPS",
  "NetworkSettings.SecondaryIPv6Addresses": "_INSTANCE_SECONDARY_IPV6_ADDRS",
  "NetworkSettings.EndpointID":             "_INSTANCE_ENDPOINTID",
  "NetworkSettings.Gateway":                "_INSTANCE_GATEWAY",
  "NetworkSettings.GlobalIPv6Address":      "_INSTANCE_GLOBAL_IPV6_ADDRESS",
  "NetworkSettings.GlobalIPv6PrefixLen":    "_INSTANCE_GLOBAL_IPV6_PREFIX_LEN",
  "NetworkSettings.IPAddress":              "_INSTANCE_IPADDRESS",
  "NetworkSettings.IPPrefixLen":            "_INSTANCE_IP_PREFIX_LEN",
  "NetworkSettings.IPv6Gateway":            "_INSTANCE_IPV6_GATEWAY",
  "NetworkSettings.MacAddress":             "_INSTANCE_MAC",
  "NetworkSettings.Networks":               "_INSTANCE_NETWORKS"
}.toOrderedTable()

proc getBoxType(b: Box): Con4mType =
  case b.kind
  of MkStr:   return stringType
  of MkInt:   return intType
  of MkFloat: return floatType
  of MkBool:  return boolType
  of MkSeq:
    var itemTypes: seq[Con4mType]
    let l = unpack[seq[Box]](b)

    if l.len() == 0:
      return newListType(newTypeVar())

    for item in l:
      itemTypes.add(item.getBoxType())
    for item in itemTypes[1..^1]:
      if item.unify(itemTypes[0]).isBottom():
        return Con4mType(kind: TypeTuple, itemTypes: itemTypes)
    return newListType(itemTypes[0])
  of MkTable:
    # This is a lie, but con4m doesn't have real objects, or a "Json" / Mixed
    # type, so we'll just continue to special case dicts.
    return newDictType(stringType, newTypeVar())
  else:
    return newTypeVar() # The JSON "Null" can stand in for any type.

proc checkAutoType(b: Box, t: Con4mType): bool =
  return not b.getBoxType().unify(t).isBottom()

const hashHeader = "sha256:"

template extractShaHashMap(value: Box): Box =
  let list     = unpack[seq[string]](value)
  var outTable = OrderedTableRef[string, string]()

  for item in list:
    let ix = item.find(hashHeader)
    if ix == -1:
      warn("Unrecognized item in _REPO_DIGEST array: " & item)
      continue
    let
      k = item[0 ..< ix - 1] # Also chop off the @
      v = item[ix + len(hashHeader) .. ^1]

    outTable[k] = v

  pack(outTable)

template extractShaHash(value: Box): Box =
  let asStr = unpack[string](value)

  if not asStr.startsWith(hashHeader):
    value
  else:
    pack[string](asStr[len(hashHeader) .. ^1])

template extractShaHashList(value: Box): Box =
  let list    = unpack[seq[string]](value)
  var outList = seq[string](@[])

  for item in list:
    if not item.startsWith(hashHeader):
      outList.add(item)
    else:
      outList.add(item[len(hashHeader) .. ^1])

  pack[seq[string]](outList)

proc jsonOneAutoKey(node:        JsonNode,
                    chalkKey:    string,
                    dict:        ChalkDict,
                    reportEmpty: bool) =

  if not chalkKey.isSubscribedKey():
    return
  var value = node.nimJsonToBox()

  if value.kind == MkObj: # Using this to represent 'null' / not provided
    return

  # Handle any transformations we know we need.
  case chalkKey
  of "_REPO_DIGESTS":
    value = extractShaHashMap(value)
  of "_IMAGE_HOSTNAMES":
    value = extractShaHashList(value)
  of "_IMAGE_NAME":
    value = extractShaHash(value)
  else:
    discard

  if not reportEmpty:
    case value.kind
    of MkStr:
      if unpack[string](value) == "": return
    of MkSeq:
      if len(unpack[seq[Box]](value)) == 0: return
    of MkTable:
      if len(unpack[OrderedTableRef[string, Box]](value)) == 0: return
    else:
      discard

  if not value.checkAutoType(chalkConfig.keyspecs[chalkKey].`type`):
    warn("Docker-provided JSON associated with chalk key '" & chalkKey &
      "' is not of the expected type.  Using it anyway.")

  dict[chalkKey] = value

proc getPartialJsonObject(top: JSonNode, key: string): Option[JSonNode] =
  var cur = top

  let keyParts = key.split('.')
  for item in keyParts:
    if item notin cur:
      return none(JSonNode)
    cur = cur[item]

  return some(cur)

proc jsonAutoKey(map:  OrderedTable[string, string],
                 top:  JsonNode,
                 dict: ChalkDict) =
  let reportEmpty = chalkConfig.dockerConfig.getReportEmptyFields()

  for jsonKey, chalkKey in map:
    let subJsonOpt = top.getPartialJsonObject(jsonKey)

    if subJsonOpt.isNone():
      continue

    jsonOneAutoKey(subJsonOpt.get(), chalkKey, dict, reportEmpty)

proc inspectImage(dict: ChalkDict, id: string, chalk: ChalkObj) =
  let
    output   = runDockerGetOutput(@["inspect", id, "--format", "json"])
    contents = output.parseJson().getElems()[0]

  chalk.cachedHash = contents["Id"].getStr().extractDockerHash()
  chalk.setIfNeeded("_IMAGE_ID", chalk.cachedHash)
  chalk.setIfNeeded("_OP_ALL_IMAGE_METADATA", contents.nimJsonToBox())
  chalk.setIfNeeded("_OP_ARTIFACT_TYPE", artTypeDockerImage)

  jsonAutoKey(dockerImageAutoMap, contents, dict)

proc inspectContainer(dict: ChalkDict, id: string, chalk: ChalkObj) =
  let
    output   = runDockerGetOutput(@["container", "inspect", id, "--format",
                                    "json"])
    contents = output.parseJson().getElems()[0]

  chalk.cachedHash = contents["Image"].getStr().extractDockerHash()
  chalk.setIfNeeded("_IMAGE_ID", chalk.cachedHash)
  chalk.setIfNeeded("_OP_ALL_CONTAINER_METADATA", contents.nimJsonToBox())
  chalk.setIfNeeded("_OP_ARTIFACT_TYPE", artTypeDockerContainer)

  jsonAutoKey(dockerContainerAutoMap, contents, dict)


method getRunTimeArtifactInfo*(self:  CodecDocker,
                               chalk: ChalkObj,
                               ins:   bool): ChalkDict =

  result = ChalkDict()

  if chalk.containerId != "":
    result.inspectContainer(chalk.containerId, chalk)
    if chalk.cachedHash != "":
      chalk.imageId = chalk.cachedHash
  if chalk.imageId != "":
    result.inspectImage(chalk.imageId, chalk)
  elif chalk.tagRef != "":
    result.inspectImage(chalk.tagRef, chalk)



registerPlugin("docker", CodecDocker())
