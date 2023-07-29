#!/bin/bash

set -uo pipefail
IFS=$'\n'

distro=""
includeIgnored=false
mergeFiles=false
mergeDirectories=false
push=false
dotfilesPath="/mnt/Data/short-files/config/static/system/setup/dotfiles"
declare -a configFiles
declare -a configDirectories

configure() {
    [[ "$distro" == "artix" ]] || [[ "$distro" == "linux-mint" ]] || { echo -e "The specified GNU/Linux distro is not supported\nTry \`scf.sh -h\` for more information"; exit; }
    local configFilesPath="$HOME/Tools/scripts/synchronize-config-files/$distro/config-files.txt"
    local configDirectoriesPath="$HOME/Tools/scripts/synchronize-config-files/$distro/config-directories.txt"
    while IFS=',' read -r column1 column2 column3 column4; do
        local column=""
        for i in {1..2}; do
            column="column$i"
            [ -n "${!column}" ] && configFiles+=("${!column}")
        done
        for i in {3..4}; do
            column="column$i"
            [ -n "${!column}" ] && configDirectories+=("${!column}")
        done
    done < <(paste -d ',' "$configFilesPath" "$configDirectoriesPath")
}

# Some commands such as `mkdir`, `rsync -az` or `ln` needs `eval` to expand paths with tildes

push_files() {
    for (( i=0; i<"${#configFiles[@]}"; i+=2 )); do
        # https://www.shellcheck.net/wiki/SC2115
        rm -rf "${dotfilesPath:?}/$distro${configFiles[i+1]}"
    done
    for (( i=0; i<"${#configFiles[@]}"; i+=2 )); do
        mkdir -p "${dotfilesPath:?}/$distro${configFiles[i+1]%/*}"
        rsync -az "$HOME${configFiles[i]#*!}" "${dotfilesPath:?}/$distro${configFiles[i+1]}"
    done
}

push_directories() {
    for (( i=0; i<"${#configDirectories[@]}"; i+=2 )); do
        rm -rf "${configDirectories[i+1]}"
    done
    for (( i=0; i<"${#configDirectories[@]}"; i+=2 )); do
        mkdir -p "${dotfilesPath:?}/$distro${configDirectories[i+1]}"
        rsync -az -r "$HOME${configDirectories[i]}" "${dotfilesPath:?}/$distro${configDirectories[i+1]%/*}"
    done
}

merge_files() {
    for (( i=0; i<"${#configFiles[@]}"; i+=2 )); do
        [ "$includeIgnored" = false ] && grep -q "!" <<< "${configFiles[i]}" && continue
        rm -f "$HOME${configFiles[i]#*!}"
    done
    for (( i=0; i<"${#configFiles[@]}"; i+=2 )); do
        [ "$includeIgnored" = false ] && grep -q "!" <<< "${configFiles[i]}" && continue
        mkdir -p "$HOME$(grep -Po '!?\K.*(?=/[^/])' <<< "${configFiles[i]}")"
        rsync -az "${dotfilesPath:?}/$distro${configFiles[i+1]#*!}" "$HOME${configFiles[i]#*!}"
    done
}

merge_directories() {
    for (( i=0; i<"${#configDirectories[@]}"; i+=2 )); do
        rm -rf "$HOME${configDirectories[i]}"
    done
    for (( i=0; i<"${#configDirectories[@]}"; i+=2 )); do
        mkdir -p "$HOME${configDirectories[i]%/*}"
        rsync -az -r "${dotfilesPath:?}/$distro${configDirectories[i+1]}" "$HOME${configDirectories[i]%/*}"
    done
}

documentation() {
cat << 'EOF'
Supported GNU/Linux distros
- Codenames: artix, linux-mint
To avoid conflicts with other synchronization services, you can exclude certain paths by preceding them with an exclamation mark '!' in the program configuration files
- This function is not available for system configuration directories
OPTIONS
    -h: Displays documentation
    -p: Exports system configuration
    --include-ignored: Imports ignored system configuration files. Option must precede --merge-files
    --merge-files: Imports system configuration files
    --merge-directories: Imports system configuration directories
EOF
}

while getopts ":h-:p:" flag; do
    case "${flag}" in
        h ) documentation; exit;;
        - )
            case "${OPTARG}" in
                include-ignored )
                    includeIgnored=true
                    [ "$mergeFiles" = true ] && { echo "ERROR: Option must precede --merge-files"; exit; }
                ;;
                merge-files )
                    [[ "${!OPTIND}" != -* ]] && distro="${!OPTIND}" && OPTIND=$((OPTIND + 1))
                    mergeFiles=true
                ;;
                merge-directories )
                    [[ "${!OPTIND}" != -* ]] && distro="${!OPTIND}" && OPTIND=$((OPTIND + 1))
                    mergeDirectories=true
                ;;
            esac
        ;;
        p )
            distro="${OPTARG}"
            push=true
        ;;
        * ) echo -e "Unrecognized option\nTry \`scf.sh -h\` for more information"; exit;;
    esac
done

if [ "$includeIgnored" = true ]; then
    if [ -z "${2:-}" ] || [ "$mergeDirectories" = true ] || [ "$push" = true ]; then
        echo -e "ERROR: Improper usage of --include-ignored\nTry \`scf.sh -h\` for more information"; exit
    fi
elif [ "$mergeFiles" = true ]; then
    configure
    merge_files
elif [ "$mergeDirectories" = true ]; then
    configure
    merge_directories
elif [ "$push" = true ]; then
    configure
    push_files && push_directories
else
    echo -e "Unrecognized option\nTry \`scf.sh -h\` for more information"
fi
