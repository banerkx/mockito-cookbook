#!/bin/bash

declare -r SCRIPT=${0##*/}

function set_color_variables
{
  if [[ ! -v ESCAPE ]]
  then
    declare -rg ESCAPE=""
  fi
  if [[ ! -v STOP_COLOR ]]
  then
    declare -rg STOP_COLOR="${ESCAPE}[0m"
  fi
  if [[ ! -v RED ]]
  then
    declare -rg RED="${ESCAPE}[0;31m"
  fi
  if [[ ! -v YELLOW ]]
  then
    declare -rg YELLOW="${ESCAPE}[1;33m"
  fi
  if [[ ! -v GREEN ]]
  then
    declare -rg GREEN="${ESCAPE}[0;32m"
  fi
}

# ${1} - message
# ${2} - message level
# ${3} - line number (optional)
function log_message
{
  local message_level=${2}
  if [[ -t 1 ]]
  then
    case ${2} in
      ERROR   ) message_level=${RED}${message_level}${STOP_COLOR};;
      WARNING ) message_level=${YELLOW}${message_level}${STOP_COLOR};;
      INFO    ) message_level=${GREEN}${message_level}${STOP_COLOR};;
      *       ) :;;
    esac
  fi

################################################################################
# NOTE: Want to replace the value of the HOME environment variable with the    #
#       literal string '${HOME}' in the message.                               #
################################################################################
  local stack="${SCRIPT}"
  local message="${message_level}: ${1//${HOME}/\$\{HOME\}}"
  message="${message//${USER}/\$\{USER\}}"
  if [[ -n "${3}" ]]
  then
    message="Line = [${3}] ${message}"
  fi

  local -i index
  for ((index = $((${#FUNCNAME[@]} - 1)); index >= 0; index--))
  do
    if [[ 0 -eq ${index} ]]
    then
      break
    fi
    case ${FUNCNAME[${index}]} in
      log_info | log_warning | log_error | log_message ) break;;
      *                                                ) stack+="::${BASH_LINENO[${index}]}->${FUNCNAME[${index}]}";;
    esac
  done
  stack="[${stack}] "
  echo "${stack}${message}"
  return 0
}

# ${1} - error message
# ${2} - line number (optional)
function log_error
{
  log_message "${1}" ERROR "${2}"
  return 0
}

# ${1} - warning message
# ${2} - line number (optional)
# NOTE: Left in for possible future use.
# shellcheck disable=SC2317
function log_warning
{
  log_message "${1}" WARNING "${2}"
  return 0
}

# ${1} - info message
# ${2} - line number (optional)
function log_info
{
  log_message "${1}" INFO "${2}"
  return 0
}

################################################################################
# PURPOSE:                                                                     #
# Print script usage information.                                              #
#                                                                              #
# INPUT VARIABLES:                                                             #
# ${1} - the exit code                                                         #
#                                                                              #
# OUTPUT:                                                                      #
# Usage information to stdout will be printed and then this                    #
# script will exit with a status of ${1}.                                      #
################################################################################
function usage
{
  cat << EOF
  Lints and beautifies the specified XML file.
  Usage: ${SCRIPT} -t,--toolchains [Maven toolchains.xml file] -h,--help
  -t,--toolchains Maven toolchains.xml file. Required.
  -h,--help       Print this usage information and exit. Takes precedence over all
                  other options. Optional.
EOF
  exit "${1}"
}

################################################################################
# PURPOSE:                                                                     #
# Parses this script's command line options.                                   #
#                                                                              #
# ARGUMENTS:                                                                   #
# ${@} - this script's command line                                            #
################################################################################
function parse_command_line_options
{
################################################################################
# Setting the long versions of the command line options.                       #
# NOTE: An option followed by a ':' means the option takes a required          #
#       argument.                                                              #
#       An option followed by a "::" means the option takes an optional        #
#       argument (for such an argument use "shift 2" instead of "shift 1" in   #
#       the getopt while loop).                                                #
################################################################################
  local long_options="toolchains:,help"

################################################################################
# To get the short options that correspond to the long options, we basically   #
# just get the first letter of each long option.                               #
#                                                                              #
# NOTE: If more than one long option begins with the same letter, then you     #
#       must:                                                                  #
#         - only assign one of these long options to long_options              #
#         - extract the short options from long_options as usual               #
#         - manually assign the remaining long options to long_options and     #
#           update short_options as appropriate                                #
################################################################################
  local short_options=$(echo "${long_options}" | tr ',' '\n' | sed 's/\(^.\)\(.*[^:]\)\(:\{0,2\}$\)/\1\3/' | tr -d '\n')

################################################################################
# --longoptions → specifies long options                                       #
# --alternative → allow long options to start with a single dash ('-') instead #
#                 of restricting long options to only "--"                     #
# --name        → program name to use for error messages                       #
# --options     → specifies short options                                      #
# --quiet       → disable error reporting (we will perform our own error       #
#                 reporting)                                                   #
# :             → exactly one required argument for the option                 #
# ::            → exactly one optional argument for the option                 #
#                 NOTE: Must use like: -o23 OR --option=23                     #
#                                                                              #
# NOTE: Options present on the command line but not specified in opts will not #
#       end up in opts.                                                        #
################################################################################
  opts=$(getopt --alternative --name "${SCRIPT}" --options "${short_options}" --longoptions "${long_options}" -- "${@}")
  if [[ ${?} != 0 ]]
  then
    log_error "Could not parse the command line option(s) [${*}]. Exiting." "${LINENO}"
    usage 1
  fi

################################################################################
# Preserves white space in opts.                                               #
################################################################################
  eval set -- "${opts}"

  while [[ true ]]
  do
    case ${1} in
      -t | --toolchains ) declare -rg TOOL_CHAINS="${2}"
                          shift 2;;

      -h | --help       ) usage 0;;

################################################################################
# End of opts marker is "--".                                                  #
################################################################################
      --                ) shift 1
                          break;;

      *                 ) log_error "Unknown internal [getopt] error. Exiting." "${LINENO}"
                          usage 1;;
    esac
  done

  if [[ ! -v TOOL_CHAINS ]]
  then
    log_error "Must specify a Maven toolchains.xml file. Exiting." "${LINENO}"
    usage 1
  fi

  if [[ ! -e "${TOOL_CHAINS}" ]]
  then
    log_error "The specified toolchains file [${TOOL_CHAINS}] does not exist. Exiting." "${LINENO}"
    exit 1
  fi

  if [[ ! -r "${TOOL_CHAINS}" ]]
  then
    log_error "The specified toolchains file [${TOOL_CHAINS}] is not readable. Exiting." "${LINENO}"
    exit 1
  fi
}

# Sets and checks the platform
function set_platform
{
  local platform=$(uname)
  case ${platform} in
    CYGWIN_NT-*  ) PLATFORM="cygwin";;
    MINGW64_NT-* ) PLATFORM="git-bash"
################################################################################
# Cygwin binaries do not always work under git-bash. Therefore, all cygwin64   #
# bin directories are removed from the PATH environment variable.              #
################################################################################
                   PATH=$(echo "${PATH}" | tr ':' '\n' | grep -v "^/[a-z]/cygwin64/.*bin$" | tr '\n' ':')
                   PATH=${PATH%:};;
    Linux        ) PLATFORM="linux";;
    *            ) log_error "The platform [${platform}] is not recognized. Exiting." "${LINENO}"
                   echo ''
                   exit 1;;
  esac
  declare -rg PLATFORM="${PLATFORM}"
  return 0
}

# ${1} - command to be checked
function check_command
{
  command -v "${1}" > /dev/null
  return "${?}"
}

# ${1} - path enclosed in double quotes
function normalize_path
{
  if [[ -n "${1}" ]]
  then
    if [[ "git-bash" == "${PLATFORM}" ]]
    then
      local -r command=cygpath
      check_command "${command}"
      local -i stat=${?}
      if [[ 0 -eq ${stat} ]]
      then
        "${command}" --unix "${1//\\/\/}"
      else
        echo "${1//\\/\/}"
      fi
    else
      echo "${1}"
    fi
  else
    echo ''
  fi
}

function set_power_shell_interpreter
{
  if [[ ! -v PRE_COMMIT_POWER_SHELL_SCRIPT ]]
  then
    local ps_interps
    ps_interps+=" pwsh"
    ps_interps+=" powershell"
    ps_interps=${ps_interps# }

    local interp
    local -i stat
    for interp in ${ps_interps}
    do
      command -v "${interp}" > /dev/null
      stat=${?}
      if [[ 0 -eq ${stat} ]]
      then
################################################################################
# ${PRE_COMMIT_POWER_SHELL_SCRIPT} is used to execute a PowerShell script.     #
# ${PRE_COMMIT_POWER_SHELL_COMMAND} is used to execute a PowerShell command.   #
################################################################################
        case "${interp}" in
          pwsh       ) declare -rg PRE_COMMIT_POWER_SHELL_SCRIPT="pwsh -NoProfile";;
          powershell ) declare -rg PRE_COMMIT_POWER_SHELL_SCRIPT="powershell -NoProfile -ExecutionPolicy Bypass -File";;
          *          ) :;;
        esac
        log_info "[PowerShell] interpreter = [${interp}]." "${LINENO}"
        return 0
      fi
    done
    log_error "No [PowerShell] interpreter was found from the set {${ps_interps// /, }}. Exiting." "${LINENO}"
    exit 1
  fi
  return 0
}

function set_power_shell_utilities_xml
{
  if [[ ! -v POWER_SHELL_UTILITIES_XML ]]
  then
    declare -rg POWER_SHELL_UTILITIES_XML="${HOME}/scripts/power-shell/utilities-xml.ps1"
    if [[ ! -r "${POWER_SHELL_UTILITIES_XML}" ]]
    then
      log_error "No readable [PowerShell] script [${POWER_SHELL_UTILITIES_XML}] found. Exiting." "${LINENO}"
      exit 1
    fi
  fi
  return 0
}

# ${1} - xpath query string
# NOTE: This function is called indirectly.
# shellcheck disable=SC2317
function get_node_path
{
  echo "${1}" | sed "s/[^']*'\([^']*\)'[^']*/\1>.</g;s/^/</;s/\.<$//"
}

# ${1} - <toolchain> node number
# ${2} - toolchain type
# ${3} - toolchain id
# ${4} - toolchain JDK home
# ${5} - toolchain version
# ${6} - toolchain vendor
function print_tool_chain_info
{
  echo "===== BEGIN <toolchain> Number [${1}] ====="
  echo "type               = [${2}]"
  echo "id                 = [${3}]"
  echo "JDK HOME           = [${4}]"
  echo "version            = [${5}]"
  echo "vendor             = [${6}]"

  if [[ "jdk" == "${2}" ]]
  then
    local -i stat=0
    local -r path="$(normalize_path "${4}")"
    if [[ ! -d "${path}" ]]
    then
      log_error "The JDK HOME directory [${path}] does not exist." "${LINENO}"
      stat=1
    elif  [[ ! -d "${path}/bin" ]]
    then
      log_error "The bin directory [${path}/bin] does not exist." "${LINENO}"
      stat=1
    elif  [[ ! -x "${path}/bin/javac" ]]
    then
      log_error "The executable [${path}/bin/javac] does not exist." "${LINENO}"
      stat=1
    elif [[ -x "${path}/bin/java" ]]
    then
      local actual_vendor="$("${path}"/bin/java -XshowSettings:properties -version 2>&1 | grep "java\.vendor" | head -1 | sed 's/^.*= *//')"
      echo "actual vendor      = [${actual_vendor:-UNKNOWN}]"
    fi
  fi
  echo "=====  END  <toolchain> Number [${1}] ====="
  echo ''
  return "${stat}"
}

# ${1} - xpath query
# ${2} - <toolchain> node number
# ${3} - variable to hold value
# NOTE: This function is called indirectly.
# shellcheck disable=SC2317
function execute_xpath_query_with_xmllint
{
  local result=${3}
  local -r command=xmllint
  local result0
  result0="$(${command} --xpath "${1/XXXX/${2}}" "${TOOL_CHAINS}" 2> /dev/null)"
  local -i stat=${?}
  if [[ 0 -eq ${stat} ]]
  then
################################################################################
# Can also use:                                                                #
#   declare "${result}=${result0@Q}" # @Q --> quote the value in a way that    #
#                                             is safe to re-input into bash    #
################################################################################
    printf -v "${result}" '%s' "${result0}"
  else
    log_error "[${command}] Could not get the value of [$(get_node_path "${1}")] node from [<toolchain>] number [${2}] in Maven toolchains file [${TOOL_CHAINS}] due to error code [${stat}]." "${LINENO}"
    eval "${result}"=""
  fi
  return "${stat}"
}

# ${1} - xpath query
# ${2} - <toolchain> node number
# ${3} - variable to hold value
# NOTE: This function is called indirectly.
# shellcheck disable=SC2317
function execute_xpath_query_with_power_shell
{
  local result=${3}
  local -r command="${PRE_COMMIT_POWER_SHELL_SCRIPT} ${POWER_SHELL_UTILITIES_XML}"
  local result0
  result0="$(${command} -XPath "${1/XXXX/${2}}" -XmlFile "${TOOL_CHAINS}" 2> /dev/null)"
  local -i stat=${?}
  if [[ 0 -eq ${stat} ]]
  then
################################################################################
# Can also use:                                                                #
#   declare "${result}=${result0@Q}" # @Q --> quote the value in a way that    #
#                                             is safe to re-input into bash    #
################################################################################
    printf -v "${result}" '%s' "${result0}"
  else
    log_error "[${command%% *}] Could not get the value of [$(get_node_path "${1}")] node from [<toolchain>] number [${2}] in Maven toolchains file [${TOOL_CHAINS}] due to error code [${stat}]." "${LINENO}"
    eval "${result}"=""
  fi
  return "${stat}"
}

function analyze_tool_chains
{
  local -i count
  ${XPATH_QUERY_FUNCTION} "${XPATH_TOOL_CHAIN_COUNT}" 0 count
  local -i stat=${?}
  if [[ 0 -eq ${stat} ]]
  then
    log_info "Maven toolchains file [${TOOL_CHAINS}] has [${count}] [<toolchain>] entries." "${LINENO}"
  else
    log_error "Could not determine the number of [<toolchain>] entries in Maven toolchains file [${TOOL_CHAINS}]. Exiting." "${LINENO}"
    exit 1
  fi

  local type
  local jdk_home
  local id
  local version
  local vendor

  local -i cum_stat=0
  local -i stat=0
  local path
  for ((i = 1; i <= ${count}; i++))
  do
    ${XPATH_QUERY_FUNCTION} "${XPATH_TYPE}" "${i}" type
    stat=${?}
    if [[ 0 -ne ${stat} ]]
    then
      cum_stat=1
      continue
    fi

    if [[ "jdk" == "${type}" ]]
    then
      ${XPATH_QUERY_FUNCTION} "${XPATH_JDK_HOME}" "${i}" jdk_home
      stat=${?}
      if [[ 0 -ne ${stat} ]]
      then
        cum_stat=1
        continue
      fi
    else
      jdk_home="N/A"
    fi

    ${XPATH_QUERY_FUNCTION} "${XPATH_ID}" "${i}" id
    stat=${?}
    if [[ 0 -ne ${stat} ]]
    then
      cum_stat=1
      continue
    fi

    if [[ "jdk" == "${type}" ]]
    then
      ${XPATH_QUERY_FUNCTION} "${XPATH_VERSION}" "${i}" version
      stat=${?}
      if [[ 0 -ne ${stat} ]]
      then
        cum_stat=1
        continue
      fi
    else
      version="N/A"
    fi

    if [[ "jdk" == "${type}" ]]
    then
      ${XPATH_QUERY_FUNCTION} "${XPATH_VENDOR}" "${i}" vendor
      stat=${?}
      if [[ 0 -ne ${stat} ]]
      then
        cum_stat=1
        continue
      fi
    else
      vendor="N/A"
    fi

    print_tool_chain_info "${i}" "${type}" "${id}" "${jdk_home}" "${version}" "${vendor}"
    stat=${?}
    if [[ 0 -ne ${stat} ]]
    then
      cum_stat=1
    fi
  done
  return "${cum_stat}"
}

function set_xpath_queries
{
  declare -rg XPATH_TOOL_CHAIN_COUNT="count(/*[local-name()='toolchains']/*[local-name()='toolchain'])"
  declare -rg XPATH_TYPE="/*[local-name()='toolchains']/*[local-name()='toolchain'][XXXX]/*[local-name()='type']/text()"
  declare -rg XPATH_ID="/*[local-name()='toolchains']/*[local-name()='toolchain'][XXXX]/*[local-name()='provides']/*[local-name()='id']/text()"
  declare -rg XPATH_VERSION="/*[local-name()='toolchains']/*[local-name()='toolchain'][XXXX]/*[local-name()='provides']/*[local-name()='version']/text()"
  declare -rg XPATH_VENDOR="/*[local-name()='toolchains']/*[local-name()='toolchain'][XXXX]/*[local-name()='provides']/*[local-name()='vendor']/text()"
  declare -rg XPATH_JDK_HOME="/*[local-name()='toolchains']/*[local-name()='toolchain'][XXXX]/*[local-name()='configuration']/*[local-name()='jdkHome']/text()"
}

function set_xpath_query_function
{
  case "${PLATFORM}" in
    cygwin   ) check_command xmllint
               stat=${?}
               if [[ 0 -eq ${stat} ]]
               then
                 declare -rg XPATH_QUERY_FUNCTION=execute_xpath_query_with_xmllint
               else
                 log_error "Could not find command [xmllint]; can not analyze toolchains file [${TOOL_CHAINS}]. Exiting." "${LINENO}"
                 exit 1
               fi;;
    linux    ) check_command xmllint
               stat=${?}
               if [[ 0 -eq ${stat} ]]
               then
                 declare -rg XPATH_QUERY_FUNCTION=execute_xpath_query_with_xmllint
               else
                 set_power_shell_interpreter
                 set_power_shell_utilities_xml
                 declare -rg XPATH_QUERY_FUNCTION=execute_xpath_query_with_power_shell
               fi;;
    *        ) set_power_shell_interpreter
               set_power_shell_utilities_xml
               declare -rg XPATH_QUERY_FUNCTION=execute_xpath_query_with_power_shell;;
  esac
}

################################################################################
# "main"                                                                       #
################################################################################
set_color_variables
parse_command_line_options "${@}"
set_platform
set_xpath_queries
set_xpath_query_function
analyze_tool_chains
declare -ir STAT=${?}
exit "${STAT}"

