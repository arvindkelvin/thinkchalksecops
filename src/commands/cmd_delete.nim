import ../config, ../collect, ../reporting, ../plugin_api

proc runCmdDelete*(path: seq[string]) {.exportc,cdecl.} =
  setContextDirectories(path)
  initCollection()

  # See runCmdInsert for info on this.
  var toRm: seq[ChalkObj] = @[]

  for item in artifacts(path):
    if item.fsRef == "":
      continue
    if not item.isMarked():
      info(item.fsRef & ": no chalk mark to delete.")
      continue
    try:
      if "$CHALK_IMPLEMENTATION_NAME" in item.extract:
        warn(item.fsRef & ": Is a chalk exe and cannot be unmarked.")
        item.opFailed = true
        toRm.add(item)
        continue
      else:
        item.myCodec.handleWrite(item, none(string))
        if not item.opFailed:
          info(item.fsRef & ": chalk mark successfully deleted")
    except:
      error(item.fsRef & ": deletion failed: " & getCurrentExceptionMsg())
      dumpExOnDebug()
      item.opFailed = true

  doReporting()
