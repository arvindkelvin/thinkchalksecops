## This variable represents the current config.  The con4m
## macro will also inject a variable with more config state, which we
## will use for config file layering.
##
## This will create a number of types for us.
##
## TODO: Add a field to the global or a section to configure
## logging options.


import nimutils/box

var samiConfig = con4m(Sami, baseconfig):
  attr(config_path,
       [string],
       @[".", "~"],
       doc = "The path to search for other config files. " &
       "This can be specified at the command-line with an early flag."
  )
  attr(config_filename,
       string,
       "sami.conf",
       doc = "The config filename; also can be set from the command line")
  attr(default_command, string,
       required = false,
       doc = "When this command runs, if no command is provided, " &
             "which one runs?") # Currently not hooked up.
  attr(color, bool, false, doc = "Do you want ansi output?")
  attr(log_level, string, "warn")
  attr(dry_run, bool, false)
  attr(artifact_search_path, [string], @["."])
  attr(recursive, bool, true)
  attr(can_dump, bool, true)
  attr(can_load, bool, true)
  attr(allow_external_config, bool, true)
  section(key, allowedSubSections = @["*", "*.json", "*.binary"]):
    attr(required,
         bool,
         defaultVal = false,
         doc = "When true, fail to WRITE a SAMI if no value is found " &
           "for the key via any allowed plugin.")
    attr(missing_action,
         string,
         defaultVal = "warn",
         doc = "What to do if, when READING a SAMI, we do not see this key")
    attr(system,
         bool,
         defaultVal = false,
         doc = "these fields CANNOT be customzied in any way;" &
               "the system sets them outside the scope of the plugin system.")
    attr(squash,
         bool,
         doc = "If there's an existing SAMI we are incorporating, " &
         "remove this key in the old SAMI if squash is true when possible",
         defaultVal = true,
         lockOnWrite = true)
    attr(standard,
         bool,
         defaultVal = false,
         doc = "These fields are part of the draft SAMI standard, " &
               "meaning they are NOT custom fields.  If you set " &
               "this to 'true' and it's not actually standard, your " &
               "key is never getting written!")
    attr(must_force,
         bool,
         defaultVal = false,
         doc = "If this is true, the key only will be turned on if " &
              "a command-line flag was passed to force adding this flag.")
    attr(skip,
         bool,
         defaultVal = false,
         doc = "If not required by the spec, skip writing this key," &
               " even if its value could be computed. Will also be " &
               "skipped if found in a nested SAMI")
    attr(in_ref,
         bool,
         defaultVal = false,
         doc = "If the key is to be injected, should it appear in the pointer" &
               " (if used; ignored otherwise)?")
    attr(output_order,
         int,
         defaultVal = 500,
         doc = "Lower numbers go first. Each provided value must be unique.")
    attr(since,
         string,
         required = false,
         doc = "When did this get added to the spec (if it's a spec key)")
    attr(type, string, lockOnWrite = true, required = true)
    attr(value,
         @x,
         doc = "This is the value set when the 'conffile' plugin runs. " &
           "The conffile plugin can handle any key, but you can still " &
           "configure it to set priority ordering, so you have fine-" &
           "grained control over when the conf file takes precedence " &
           "over the other plugins.",
         required = false)
    attr(codec,
         bool,
         defaultVal = false,
         doc = "If true, then this key is settable by plugins marked codec.")
    attr(docstring,
         string,
         required = false,
         doc = "documentation for the key.")
  section(plugin, allowedSubSections = @["*"]):
    attr(priority,
         int,
         required = true,
         defaultVal = 50,
         doc = "Vs other plugins, where should this run?  Lower goes first")
    attr(codec,
         bool,
         required = true,
         defaultVal = false,
         lockOnWrite = true)
    attr(enabled, bool, defaultVal = true, doc = "Turn off this plugin.")
    attr(command,
         string,
         required = false)
    attr(keys,
         [string],
         required = true,
         lockOnWrite = true)
    attr(overrides,
         {string: int}, required = false)
    attr(ignore,
         [string],
         required = false)
    attr(docstring,
         string,
         required = false)
    
  section(sink, allowedSubSections = @["*"]):
    attr(uses_secret, bool, defaultVal = false)
    attr(uses_userid, bool, defaultVal = false)
    attr(uses_filename, bool, defaultVal = false)
    attr(uses_uri, bool, defaultVal = false)
    attr(uses_region, bool, defaultVal = false)
    attr(uses_headers, bool, defaultVal = false)
    attr(uses_cacheid, bool, defaultVal = false)        
    attr(uses_aux, bool, defaultVal = false)
    attr(needs_secret, bool, defaultVal = false)
    attr(needs_userid, bool, defaultVal = false)
    attr(needs_filename, bool, defaultVal = false)
    attr(needs_uri, bool, defaultVal = false)
    attr(needs_region, bool, defaultVal = false)
    attr(needs_aux, bool, defaultVal = false)
    attr(needs_headers, bool, defaultVal = false)
    attr(needs_cacheid, bool, defaultVal = false)        
    attr(docstring, string, required = false)
    
  section(outhook, allowedSubSections = @["*"]):
    attr(sink, string, required = true)
    attr(filters, [string], defaultVal = @[])
    attr(secret, string, required = false)
    attr(userid, string, required = false)
    attr(filename, string, required = false)
    attr(uri, string, required = false)
    attr(region, string, required = false)
    attr(headers, string, required = false)
    attr(cacheid, string, required = false)
    attr(aux, string, required = false)
    attr(stop, bool, defaultVal = false)
    attr(docstring, string, required = false)
    attr(filters, [string], defaultVal = @[])