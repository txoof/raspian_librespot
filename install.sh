#!/usr/bin/env bash

# -u: treat unset variables as an error and exit immediately
# -e: exit when command fails
set -eu

# print commands prior to executing (for debuging)
#set -x

REPO=https://github.com/librespot-org/librespot.git

LS_TEMP_DIR="/tmp/librespot"
SCRIPT_PATH=$(dirname "$(readlink -f "$0")")

DPKGS=("git" "build-essential" "libasound2-dev" "pkg-config" "libpulse-dev" )

# output directory for built librespot
CARGO_TARGET=$LS_TEMP_DIR/target/release/librespot

abort() {
  local exit_code=${1:-0}
  local message=${2:-"Aborting gracefully"}
  echo "$message with exit code $exit_code"
  if [[ $exit_code -ne 0 ]]
  then
    echo "To restart this installer run: $ $SCRIPT_PATH"
  fi

  exit "$exit_code"
}

copy_files() {
  local items=($1)
  local prefix=$2

	echo "Copy these files from raspotify into the local system"

  for item in "${items[@]}"; do
    echo "${prefix}${item}*"
  done
}

install_dpkg() {
  local packages=("$@")
  local packages_to_install=()

  echo "Checking build dependencies"
  for package in "${packages[@]}"; do
    if ! dpkg -s "$package" >/dev/null 2>&1; then
      packages_to_install+=("$package")
    fi
  done

  if [[ ${#packages_to_install[@]} -eq 0 ]]; then
    echo "All dependencies are already installed."
  else
    echo "Installing the following packages: ${packages_to_install[*]}"
    sudo apt-get install "${packages_to_install[@]}" || abort 1 "failed to install packages"
  fi
}

check_git_repo() {
  local directory=$1

  if [ -d "$directory/.git" ]; then
    # Directory is a Git repository
    echo "$directory is a Git repository"

    # Change to the repository directory
    cd "$directory"

    # Get the default branch name
    default_branch=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')

    # Check if the repository is up to date
    if git diff --quiet @{upstream} 2>&1; then
      echo "Repository is up to date"
      return 0
    else
      echo "Repository is not up to date. Updating to the default branch: $default_branch"
      git pull origin "$default_branch" && return 0 || return 1 
    fi
  else
    echo "$directory is not a Git repository"
    return 1
  fi
}


install_rust() {
  echo Installing Rust
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  if ! test_command "cargo -V";
  then
    abort 1 "Rust failed to install see: https://users.rust-lang.org/t/no-such-file-or-directory-os-error-2-cargo-or-rust-run/93465"
  fi

}

test_command() {
  local command="$1"
  if eval "$command" >  /dev/null 2>&1; then
    # succss, exit 0
    return 0
  else
    # failure, exit 1
    return 1
  fi
}

check_apt_cache() {
  local minutes=${1:-60}
  local cache_age=$(stat -c %Y /var/cache/apt/pkgcache.bin)
  local current_time=$(date +%s)
  local time_diff=$(( (current_time - cache_age) / 60 ))

  if (( time_diff >= minutes )); then
    echo "Apt cache is older than $minutes minutes. Updating..."
    sudo apt update
  else
    echo "Apt cache is up to date. Skipping update."
  fi
}


echo This script will compile and install Librespot and start it running as a daemon. 

install_dpkg "${DPKGS[@]}"

if ! test_command "cargo -V";
then
  install_rust
fi


# Check if temp directory already exists and repos are updated
if [ ! -d "$LS_TEMP_DIR" ];
then
  echo "Cloning $REPO into $LS_TEMP_DIR"
  git clone $REPO $LS_TEMP_DIR
else
  cd "$LS_TEMP_DIR" || abort 1 "$LS_TEMP_DIR exists, but is not accessible"
fi


echo "Building with cargo..."
if [ ! -f $CARGO_TARGET ]
then
  echo "build..."
  cargo build --release --jobs "$(nproc)" --no-default-features --features "alsa-backend pulseaudio-backend"
else
  echo $CARGO_TARGET already exists
fi

# source files from raspotify
#copy_files "${items[*]}" "$LS_TEMP_DIR/raspotify


