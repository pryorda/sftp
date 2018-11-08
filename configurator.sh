#!/bin/bash -e
# Paths
mkdir -p /etc/sftp/
userConfPath="/etc/sftp/users.conf"
# touch userConfPath so inotify will watch it
touch "${userConfPath}"
userConfPathLegacy="/etc/sftp-users.conf"
userConfFinalPath="/var/run/sftp/users.conf"

# Extended regular expression (ERE) for arguments
reUser='[A-Za-z0-9._][A-Za-z0-9._-]{0,31}' # POSIX.1-2008
rePass='[^:]{0,255}'
reUid='[[:digit:]]*'
reGid='[[:digit:]]*'
reDir='[^:]*'
# shellcheck disable=SC2034
reArgs="^($reUser)(:$rePass)(:e)?(:$reUid)?(:$reGid)?(:$reDir)?$"
# shellcheck disable=SC2034
reArgsMaybe="^[^:[:space:]]+:.*$"            # Smallest indication of attempt to use argument
reArgSkip='^([[:blank:]]*#.*|[[:blank:]]*)$' # comment or empty line

function log() {
  timestamp=$(date +"%b %d %H:%M:%S")
  echo "${timestamp} $*"
}

function validateArg() {
  name="$1"
  val="$2"
  re="$3"

  if [[ "$val" =~ ^$re$ ]]; then
    return 0
  else
    log "ERROR: Invalid $name \"$val\", do not match required regex pattern: $re"
    return 1
  fi
}

# Create keys for user : createKeys user
function createKeys() {
  # Parse keys environment variable into key files.
  cleanUserName="${user//[.-]/'_'}"
  log "cleanUsername: ${cleanUserName} User: ${user}"
  USER_SSH_KEYS="${cleanUserName}_ssh_keys"
  if [ -n "${!USER_SSH_KEYS}" ]; then
    log "Create key files for ${user} from environment variable"
    IFS=';' read -r -a USER_KEYS <<<"${!USER_SSH_KEYS}"
    mkdir -p "/home/${user}/.ssh/keys/"
    # Remove any old keys before proceeding.
    rm -vf /home/"${user}"/.ssh/keys/*
    for index in "${!USER_KEYS[@]}"; do
      echo "${USER_KEYS[index]}" >"/home/$user/.ssh/keys/${user}_ssh_keys_${index}.pub"
    done
  fi

  # Add SSH keys to authorized_keys with valid permissions
  if [ -d "/home/${user}/.ssh/keys" ]; then
    # Reset key file so new keys can be loaded in.
    log "Create authorized_keys ${user} from key files"
    echo >"/home/${user}/.ssh/authorized_keys"
    for publickey in /home/"${user}"/.ssh/keys/*; do
      cat "${publickey}" >>"/home/${user}/.ssh/authorized_keys"
    done
    chown "${user}" "/home/${user}/.ssh/authorized_keys"
    chmod 600 "/home/${user}/.ssh/authorized_keys"
  fi
}

function createLogDevices() {
  log "Adding logs bind mount for user: $1"
  mkdir -p "/home/$1/dev"
  touch "/home/$1/dev/log"
  mount -o bind /dev/log "/home/$1/dev/log"
  log "Completed adding log mounts for user: $1"
}

function createUser() {
  log "Parsing user data for $(echo "$@" | cut -d: -f1)"

  IFS=':' read -r -a args <<<"$@"

  skipIndex=0
  chpasswdOptions=()
  useraddOptions=("--no-user-group")

  user="${args[0]}"
  validateArg "username" "$user" "$reUser" || return 1
  pass="${args[1]}"
  validateArg "password" "$pass" "$rePass" || return 1

  if [ "${args[2]}" == "e" ]; then
    chpasswdOptions+=("-e")
    skipIndex=1
  fi

  uid="${args[$((skipIndex + 2))]}"
  validateArg "UID" "$uid" "$reUid" || return 1
  gid="${args[$((skipIndex + 3))]}"
  validateArg "GID" "$gid" "$reGid" || return 1
  dir="${args[$((skipIndex + 4))]}"
  validateArg "dirs" "$dir" "$reDir" || return 1

  if getent passwd "${user}" >/dev/null; then
    log "WARNING: User ${user} already exists. Skipping creation."
  else
    if [ -n "$uid" ]; then
      useraddOptions+=("--non-unique" "--uid" "${uid}")
    fi

    if [ -n "$gid" ]; then
      if ! getent group "${gid}" >/dev/null; then
        groupadd --gid "${gid}" "group_${gid}"
      fi

      useraddOptions+=("--gid" "${gid}")
    fi

    useradd "${useraddOptions[@]}" "${user}"
    mkdir -p "/home/${user}"
    chown root:root "/home/${user}"
    chmod 755 "/home/${user}"
  fi

  # Retrieving user id to use it in chown commands instead of the user name
  # to avoid problems on alpine when the user name contains a '.'
  uid="$(id -u "${user}")"

  if [ -n "$pass" ]; then
    echo "${user}:${pass}" | chpasswd "${chpasswdOptions[@]}"
  else
    usermod -p "*" "${user}" # disabled password
  fi

  createKeys "${user}"

  # Make sure dirs exists
  if [ -n "$dir" ]; then
    IFS=',' read -r -a dirArgs <<<"${dir}"
    for dirPath in "${dirArgs[@]}"; do
      dirPath="/home/${user}/${dirPath}"
      if [ ! -d "${dirPath}" ]; then
        log "Creating directory: ${dirPath}"
        mkdir -p "${dirPath}"
        chown -R "${uid}":users "${dirPath}"
      else
        log "Directory already exists: ${dirPath}"
      fi
    done
  fi

  createLogDevices "${user}"
}

function main() {
  mkdir -p "$(dirname "${userConfFinalPath}")"

  # Append mounted config to final config
  if [ -f "$userConfPath" ] && [ "$(cat "${userConfPath}")" != "" ]; then
    log "Adding users from ${userConfPath} to ${userConfFinalPath}"
    grep -v -E "$reArgSkip" "${userConfPath}" >"${userConfFinalPath}"
  fi

  IFS=' ' read -r -a users <<<"$@"
  for user in "${users[@]}"; do
    log "Adding users from ARGS to ${userConfFinalPath}"
    echo "${user}" >>"${userConfFinalPath}"
  done

  if [ -n "${SFTP_USERS}" ]; then
    unset user
    # Append users from environment variable to final config
    log "Adding users from environment to ${userConfFinalPath}"
    IFS=' ' read -r -a usersFromEnv <<<"${SFTP_USERS}"
    for user in "${usersFromEnv[@]}"; do
      echo "${user}" >>"${userConfFinalPath}"
    done
  fi

  # Check that we have users in config
  if [[ -f "${userConfFinalPath}" ]] && [[ "$(wc -l <"${userConfFinalPath}")" -gt 0 ]]; then
    # Import users from final conf file
    log "Importing users from ${userConfFinalPath}"
    log "Users: $(wc -l <${userConfFinalPath})"
    while IFS="" read -r line || [[ -n "$line" ]]; do
      createUser "$line"
    done <"$userConfFinalPath"
  else
    log "Warning: No users provided!"
  fi

  mv -v $userConfFinalPath $userConfFinalPath.old || true
}

function runCustomScripts() {
  # Source custom scripts, if any
  if [ -d /etc/sftp.d ]; then
    for f in /etc/sftp.d/*; do
      if [ -x "$f" ]; then
        log "Running $f ..."
        $f
      else
        log "Could not run $f, because it's missing execute permission (+x)."
      fi
    done
    unset f
  fi
}

function init() {
  # Backward compatibility with legacy config path
  if [ ! -f "$userConfPath" ] && [ -f "$userConfPathLegacy" ]; then
    mkdir -p "$(dirname $userConfPath)"
    ln -s "$userConfPathLegacy" "$userConfPath"
  fi
}

init
main "$@"
runCustomScripts
inotifywait -m -e modify $userConfPath |
  while read -r events; do
    log "${events}"
    main "$@"
  done
