# This is a simple codec for dealing with python bytecode files;
#  i.e., currently ones that have the extensions .pyc, .pyo, .pyd
#
# :Author: Rich Smith (rich@crashoverride.com)
# :Copyright: 2022, 2023, Crash Override, Inc.

import strutils, options, streams, nimSHA2, ../config, ../plugins, os

when (NimMajor, NimMinor) < (1, 7): {.warning[LockLevel]: off.}

type CodecPythonPyc* = ref object of Codec

method scan*(self:   CodecPythonPyc,
             stream: FileStream,
             loc:    string): Option[ChalkObj] =

    try:
        var chalk: ChalkObj
        var ext = loc.splitFile().ext.strip()

        #Does this artefact have a python source file extension?
        # if so chalk it, else skip
        #TODO validate PYC header / magic ?
        if not ext.startsWith(".") or ext[1..^1] notin chalkConfig.getPycExtensions():
            return none(ChalkObj)

        let byte_blob = stream.readAll()

        let ix  = byte_blob.find(magicUTF8)
        if ix == -1:
            #No magic == no existing chalk, new chalk created
            chalk             = newChalk(stream, loc)
            chalk.startOffset = len(byte_blob)

        else:#Existing chalk, just reflect whats found
            stream.setPosition(ix)
            chalk             = stream.loadChalkFromFStream(loc)
        return some(chalk)
    except:
        return none(ChalkObj)

method handleWrite*(self:    CodecPythonPyc,
                    chalk:   ChalkObj,
                    encoded: Option[string],
                    virtual: bool): string =
  #Reset to start of file
  chalk.stream.setPosition(0)
  #Read up to previously set offset indicating where magic began
  let pre  = chalk.stream.readStr(chalk.startOffset)
  #Move past
  if chalk.endOffset > chalk.startOffset:
    chalk.stream.setPosition(chalk.endOffset)
  #Read entire rest of file
  let post = chalk.stream.readAll()

  var toWrite: string

  #Build up a 'toWrite' string that will replace entire file
  if encoded.isSome():
    toWrite = pre
    toWrite &= encoded.get() & post.strip(chars = {' ', '\n'}, trailing = false)
  else:
    #TODO clean up like above
    toWrite = pre[0 ..< pre.find('\n')] & post
  chalk.closeFileStream()

  #If NOT a dry-run replace file contents
  if not virtual: chalk.replaceFileContents(toWrite)

  ##Return sha256 hash
  return $(toWrite.computeSHA256())

method getArtifactHash*(self: CodecPythonPyc, chalk: ChalkObj): string =
  chalk.stream.setPosition(0)
  return $(chalk.stream.readStr(chalk.startOffset).computeSHA256())

registerPlugin("python_pyc", CodecPythonPyc())