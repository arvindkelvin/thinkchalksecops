## This plugin is responsible for providing metadata gleaned from a
## Gitlab CI environment.
##
## :Author: Rich Smith (rich@crashoverride.com) heaviily based on
## code by Miroslav Shubernetskiy (miroslav@crashoverride.com)
## :Copyright: 2022, 2023, Crash Override, Inc.


import tables, os
import nimutils, ../types, ../plugins

when (NimMajor, NimMinor) < (1, 7): {.warning[LockLevel]: off.}

type GitlabCI = ref object of Plugin

method getHostInfo*(self: GitlabCI, path: seq[string], ins: bool): ChalkDict =
  result = ChalkDict()

  # https://docs.gitlab.com/ee/ci/variables/predefined_variables.html
  let
    CI                = os.getEnv("CI")
    GITLAB_CI         = os.getEnv("GITLAB_CI")
    GITLAB_JOB_URL    = os.getEnv("CI_JOB_URL")
    GITLAB_JOB_ID     = os.getEnv("CI_JOB_ID")
    GITLAB_API_URL    = os.getEnv("CI_API_V4_URL")
    GITLAB_USER       = os.getEnv("GITLAB_USER_LOGIN")
    GITLAB_EVENT_NAME = os.getEnv("CI_PIPELINE_SOURCE")

  # probably not running in gitlab CI
  if CI == "" and GITLAB_CI == "": return

  if GITLAB_JOB_ID != "":  result["BUILD_ID"]      = pack(GITLAB_JOB_ID)

  if GITLAB_JOB_URL != "": result["BUILD_URI"]     = pack(GITLAB_JOB_URL)

  if GITLAB_API_URL != "": result["BUILD_API_URI"] = pack(GITLAB_API_URL)

  # https://docs.gitlab.com/ee/ci/jobs
  #                     /job_control.html#common-if-clauses-for-rules
  if GITLAB_EVENT_NAME != "" :
      result["BUILD_TRIGGER"] = pack(GITLAB_EVENT_NAME)

  # Lots of potential 'user' vars to pick from here, long term will likely
  #  need to be configurable as different customers will attach different
  #  meaning to different user value depending on their pipeline
  if GITLAB_USER != "": result["BUILD_CONTACT"] = pack(@[GITLAB_USER])

registerPlugin("ci_gitlab", GitlabCI())
