#!/bin/bash
# See: https://github.com/djui/bashunit

skipAllTests=false # For future use.

scriptDir="${4:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
buildDir="${scriptDir}/.."
tmpDir="/tmp/pryorda_sftp_test"

sudo="$sudo"
cache="--no-cache"

build=${1:-"build"}
output=${2:-"quiet"}
cleanup=${3:-"cleanup"}
sftpImageName=${sftpImageName:-"pryorda/sftp_test"}
sftpContainerName=${sftpContainerName:-"pryorda_sftp_test"}

if [ "$output" == "quiet" ]; then
  redirect="/dev/null"
else
  redirect="/dev/stdout"
fi

buildOptions=("--tag" "${sftpImageName}" "${cache}")

##############################################################################

function beforeTest() {
  if [ "${build}" == "build" ]; then
    buildOptions+=("--pull=true")
  fi

  $sudo docker build "${buildOptions[@]}" "$buildDir"
  status=$?
  assertEqual ${status} 0
  if [ "${status}" -gt 0 ]; then
    echo "Docker build failed."
    exit 1
  fi
  # Private key can not be read by others
  chmod go-rw "${scriptDir}/id_rsa"

  rm -rf "${tmpDir}" # clean state
  mkdir "${tmpDir}"
  # shellcheck disable=SC2129
  echo "test::$(id -u):$(id -g):dir1,dir2" >>"${tmpDir}/users"
  echo "" >>"${tmpDir}/users" # empty line
  echo "# comments are allowed" >>"${tmpDir}/users"
  echo "  " >>"${tmpDir}/users" # only whitespace
  echo "  # with whitespace in front" >>"${tmpDir}/users"
  echo "user.with.dot::$(id -u):$(id -g)" >>"${tmpDir}/users"
  $sudo docker run \
    --privileged \
    -v "${tmpDir}/users:/etc/sftp/users.conf:rw" \
    -v "${scriptDir}/id_rsa.pub":/home/test/.ssh/keys/id_rsa.pub:ro \
    -v "${scriptDir}/id_rsa.pub":/home/user-from-env/.ssh/keys/id_rsa.pub:ro \
    -v "${scriptDir}/id_rsa.pub":/home/user.with.dot/.ssh/keys/id_rsa.pub:ro \
    -v "${tmpDir}":/home/test/share \
    --name "${sftpContainerName}" \
    --expose 22 \
    -e "SFTP_USERS=user-from-env::$(id -u):$(id -g) user-from-env-2::$(id -u):$(id -g)" \
    -d "${sftpImageName}" \
    >"${redirect}"

  waitForServer "${sftpContainerName}"
}

function getSftpIp() {
  $sudo docker inspect -f "{{.NetworkSettings.IPAddress}}" "$1"
}

function runSftpCommands() {
  ip="$(getSftpIp "$1")"
  user="$2"
  shift 2

  commands=""
  for cmd in "$@"; do
    commands="${commands}${cmd}"$'\n'
  done

  echo "${commands}" | sftp \
    -i "${scriptDir}/id_rsa" \
    -oStrictHostKeyChecking=no \
    -oUserKnownHostsFile=/dev/null \
    -b - "${user}"@"${ip}" \
    >"${redirect}" 2>&1

  status=$?
  sleep 1 # wait for commands to finish
  return $status
}

function waitForServer() {
  containerName="$1"
  echo -n "Waiting for ${containerName} to open port 22 ..."

  for i in {1..30}; do
    sleep 1
    ip="$(getSftpIp "${containerName}")"
    echo -n "."
    if [ -n "${ip}" ] && nc -w 1 -z "${ip}" 22; then
      echo " OPEN. Took ${i}s."
      return 0
    fi
  done

  echo " TIMEOUT after ${i}s."
  return 1
}

function containerIsRunning() {
  ps="$($sudo docker ps -q -f name="${1}")"
  assertNotEqual "${ps}" ""
}

function showOutput() {
  if [ "$output" != "quiet" ]; then
    $sudo docker logs "$1"
  fi
}

function doCleanup() {
  if [ "$cleanup" == "cleanup" ]; then
    $sudo docker rm -fv "${1}" >"${redirect}"
  fi
}

##############################################################################

function testContainerIsRunning() {
  $skipAllTests && skip && return 0

  containerIsRunning "${sftpContainerName}"
}

function testLoginUsingSshKey() {
  $skipAllTests && skip && return 0

  runSftpCommands "${sftpContainerName}" "test" "exit"
  assertReturn $? 0
}

function testUserWithDotLogin() {
  $skipAllTests && skip && return 0

  runSftpCommands "${sftpContainerName}" "user.with.dot" "exit"
  assertReturn $? 0
}

function testLoginUsingUserFromEnv() {
  $skipAllTests && skip && return 0

  runSftpCommands "${sftpContainerName}" "user-from-env" "exit"
  assertReturn $? 0
}

function testWritePermission() {
  $skipAllTests && skip && return 0

  runSftpCommands "${sftpContainerName}" "test" \
    "cd share" \
    "mkdir test" \
    "exit"
  test -d "${tmpDir}/test"
  assertReturn $? 0
}

function testDir() {
  $skipAllTests && skip && return 0

  runSftpCommands "${sftpContainerName}" "test" \
    "cd dir1" \
    "mkdir test-dir1" \
    "get -rf test-dir1 ${tmpDir}/" \
    "cd ../dir2" \
    "mkdir test-dir2" \
    "get -rf test-dir2 ${tmpDir}/" \
    "exit"
  test -d "${tmpDir}/test-dir1"
  assertReturn $? 0
  test -d "${tmpDir}/test-dir2"
  assertReturn $? 0

  showOutput "${sftpContainerName}"
  doCleanup "${sftpContainerName}"
}

# Smallest user config possible
function testMinimalContainerStart() {
  $skipAllTests && skip && return 0

  tmpContainerName="${sftpContainerName}""_minimal"

  $sudo docker run \
    --privileged \
    --name "${tmpContainerName}" \
    -d "${sftpImageName}" \
    m: \
    >"${redirect}"

  waitForServer "${tmpContainerName}"
  containerIsRunning "${tmpContainerName}"
  showOutput "${tmpContainerName}"
  doCleanup "${tmpContainerName}"

}

function testLegacyConfigPath() {
  $skipAllTests && skip && return 0

  tmpContainerName="${sftpContainerName}""_legacy"

  echo "test::$(id -u):$(id -g)" >>"${tmpDir}/legacy_users"
  $sudo docker run \
    --privileged \
    -v "${tmpDir}/legacy_users:/etc/sftp-users.conf:rw" \
    --name "${tmpContainerName}" \
    --expose 22 \
    -d "${sftpImageName}" \
    >"${redirect}"

  waitForServer "${tmpContainerName}"
  containerIsRunning "${tmpContainerName}"
  showOutput "${tmpContainerName}"
  doCleanup "${tmpContainerName}"
}

# Bind-mount folder using script in /etc/sftp.d/
function testCustomContainerStart() {
  $skipAllTests && skip && return 0

  tmpContainerName="${sftpContainerName}""_custom"

  mkdir -p "${tmpDir}/custom/bindmount"
  echo "mkdir -p /home/custom/bindmount && \
        chown custom /home/custom/bindmount && \
        mount --bind /custom /home/custom/bindmount" \
    >"${tmpDir}/mount.sh"
  chmod +x "${tmpDir}/mount.sh"

  $sudo docker run \
    --privileged \
    --name "${tmpContainerName}" \
    -v "${scriptDir}/id_rsa.pub":/home/custom/.ssh/keys/id_rsa.pub:ro \
    -v "${tmpDir}/custom/bindmount":/custom \
    -v "${tmpDir}/mount.sh":/etc/sftp.d/mount.sh \
    --expose 22 \
    -d "${sftpImageName}" \
    custom:123 \
    >"${redirect}"

  waitForServer "${tmpContainerName}"
  containerIsRunning "${tmpContainerName}"

  runSftpCommands "${tmpContainerName}" "custom" \
    "cd bindmount" \
    "mkdir test" \
    "exit"

  test -d "${tmpDir}/custom/bindmount/test"
  assertReturn $? 0

  showOutput "${tmpContainerName}"
  doCleanup "${tmpContainerName}"
}

function testCustomContainerWithEnvKeysStart() {
  $skipAllTests && skip && return 0

  tmpContainerName="${sftpContainerName}""_custom_keys"
  custom_ssh_keys="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDHDDQw9a9miGWDEXLG9mMR7OuV3ufmkgm5htntuZnxRw1sUfySmgeaY5ZDvHw5uEMulxYS/yJ+hLxFgsj3tUwIlwRz9yRyrzZm+gBE4Xhsb+NhdaMQdFnMSn3cUw8UHO8FmRd4FLiSx32x+pF83JnNR67+3fzSg2wKmvz5OdoQSELn4TpRuOt4fQI+22QPRpGOuzN6vWGQazY/LzRVlKeJ1kasVE1p/GKCNwtE2nhkk3B4VzuZy4sh8Fqklcgka6PZcDGu3zqkFCgRJ9oRODSbcNaXhnXDrBlnbpaciJU4d2JdyPdTS11nAKLE+KEfnJhjLLp8TXWQzD2xB2HH7gEd test;ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDHDDQw9a9miGWDEXLG9mMR7OuV3ufmkgm5htntuZnxRw1sUfySmgeaY5ZDvHw5uEMulxYS/yJ+hLxFgsj3tUwIlwRz9yRyrzZm+gBE4Xhsb+NhdaMQdFnMSn3cUw8UHO8FmRd4FLiSx32x+pF83JnNR67+3fzSg2wKmvz5OdoQSELn4TpRuOt4fQI+22QPRpGOuzN6vWGQazY/LzRVlKeJ1kasVE1p/GKCNwtE2nhkk3B4VzuZy4sh8Fqklcgka6PZcDGu3zqkFCgRJ9oRODSbcNaXhnXDrBlnbpaciJU4d2JdyPdTS11nAKLE+KEfnJhjLLp8TXWQzD2xB2HH7gEd test"

  $sudo docker run \
    --privileged \
    --name "${tmpContainerName}" \
    -e custom_ssh_keys="${custom_ssh_keys}" \
    --expose 22 \
    -d "${sftpImageName}" \
    custom:123:::incoming \
    >"${redirect}"

  waitForServer "${tmpContainerName}"

  containerIsRunning "${tmpContainerName}"

  runSftpCommands "${tmpContainerName}" "custom" \
    "cd incoming" \
    "mkdir test" \
    "exit"
  assertReturn $? 0

  keys="$($sudo docker exec -it "${tmpContainerName}" grep ssh /home/custom/.ssh/authorized_keys | wc -l)"
  assertEqual "${keys}" 2

  showOutput "${tmpContainerName}"
  doCleanup "${tmpContainerName}"
}

function testMultipleUsersFromEnv() {
  $skipAllTests && skip && return 0

  tmpContainerName="${sftpContainerName}_users_from_env"
  SFTP_USERS="testing1:testing:1001:1001:testing testing2:testing2:1002:1002:testing testing3:testing:1003:1003:testing testing4:testing:1004:1004:testing"

  $sudo docker run \
    --privileged \
    --name "${tmpContainerName}" \
    --expose 22 \
    -e SFTP_USERS="${SFTP_USERS}" \
    -d "${sftpImageName}" \
    >"${redirect}"

  waitForServer "${tmpContainerName}"
  containerIsRunning "${tmpContainerName}"

  userID="$($sudo docker exec -it "${tmpContainerName}" id -u testing1)"
  assertStartsWith "${userID}" 1001

  userID="$($sudo docker exec -it "${tmpContainerName}" id -u testing2)"
  assertStartsWith "${userID}" 1002

  userID="$($sudo docker exec -it "${tmpContainerName}" id -u testing3)"
  assertStartsWith "${userID}" 1003

  userID="$($sudo docker exec -it "${tmpContainerName}" id -u testing4)"
  assertStartsWith "${userID}" 1004

  showOutput "${tmpContainerName}"
  doCleanup "${tmpContainerName}"
}

function testMultipleUsersFromArgs() {
  $skipAllTests && skip && return 0

  tmpContainerName="${sftpContainerName}_users_from_args"
  SFTP_USERS="testing1:testing:1001:1001:testing testing2:testing2:1002:1002:testing testing3:testing:1003:1003:testing testing4:testing:1004:1004:testing"

  $sudo docker run \
    --privileged \
    --name "${tmpContainerName}" \
    --expose 22 \
    -d "${sftpImageName}" "${SFTP_USERS}" \
    >"${redirect}"

  waitForServer "${tmpContainerName}"
  containerIsRunning "${tmpContainerName}"

  userID="$($sudo docker exec -it "${tmpContainerName}" id -u testing1)"
  assertStartsWith "${userID}" 1001

  userID="$($sudo docker exec -it "${tmpContainerName}" id -u testing2)"
  assertStartsWith "${userID}" 1002

  userID="$($sudo docker exec -it "${tmpContainerName}" id -u testing3)"
  assertStartsWith "${userID}" 1003

  userID="$($sudo docker exec -it "${tmpContainerName}" id -u testing4)"
  assertStartsWith "${userID}" 1004

  showOutput "${tmpContainerName}"
  doCleanup "${tmpContainerName}"
}

##############################################################################

# Run tests
# shellcheck source=tests/bashunit.bash
source "${scriptDir}/bashunit.bash"
# Nothing happens after this
