#!/bin/bash

set -uo pipefail
IFS=$'\n'

bold=$(tput bold); normal=$(tput sgr0); dim=$(tput dim)
date=$(printf '%(%Y-%m-%d)T\n' -1)
mapfile -t sourcePaths < ~/Tools/scripts/glacier/source.txt
mapfile -t backupDrivePath < ~/Tools/scripts/glacier/destination.txt
backupRootDirectory=""

#Generate spinner
counter=0
spin() {
    local spinner="◰◳◲◱"
    local instance=${spinner:counter++:1}
    printf "\b\b%s " "$instance"
    ((counter==${#spinner})) && counter=0
}

display_directories() {
    clear -x
    backupRootDirectory="$backupDrivePath/$date"
    echo "${bold}The following directories are going to be backed up:${normal}"
    for path in "${sourcePaths[@]}"; do
        echo "$path"
    done
    echo -e "${bold}→ $backupRootDirectory${normal}\n"
    read -rp "Continue? [Y/n] " options
    case "${options,,}" in
        n ) echo "Operation aborted";;
        * ) check_backup_existence && make_backup_directories && set_backup_description && back_up && check_integrity && clean_reports;;
    esac
}

check_backup_existence() {
    existentBackup=$(find "$backupDrivePath" -mindepth 1 -maxdepth 1 -type d -name "$date")
    if [[ -n "$existentBackup" ]]; then
        read -rp "Backup already exists, delete it or run integrity check? [D/r] " options
        case "${options,,}" in 
            d ) rm -rf "$backupRootDirectory"; exit;;
            r ) check_integrity && clean_reports; exit;;
            * ) rm -rf "$backupRootDirectory"; exit;;
        esac
    fi
}

make_backup_directories() {
    mkdir -p "$backupRootDirectory/.glacier/digests" "$backupRootDirectory/.glacier/reports"
}

get_backup_description() {
    find "$backupDrivePath" -mindepth 1 -maxdepth 1 -type d | cat -n
    read -rp "${bold}Select backup to display its description: ${normal}" option
    local backupRootDirectory; backupRootDirectory=$(find "$backupDrivePath" -mindepth 1 -maxdepth 1 -type d | awk "FNR==$option")
    cat "$backupRootDirectory/.glacier/description"
}

set_backup_description() {
    echo "Provide a description of the backup [Save with <CR><C-d>]"
    tput dim; cat > "$backupRootDirectory/.glacier/description"; tput sgr0
}

back_up() {
    clear -x
    for sourcePath in "${sourcePaths[@]}"; do
        echo Generating hash
        local expandedSourcePath; eval expandedSourcePath="$sourcePath"
        local checksumPath="$backupRootDirectory/.glacier/digests/${expandedSourcePath##*/}.sha256"
        find "$expandedSourcePath" -type f -exec sha256sum {} \+ > "$checksumPath"
        sed -i "s|$expandedSourcePath|./${expandedSourcePath##*/}|g" "$checksumPath"
        echo Tranfering to drive: "$expandedSourcePath"
        time tar -cf - --absolute-names "$expandedSourcePath" | pv | tar -xf - -C "$backupRootDirectory" --absolute-names --strip-components=2
        echo
    done
}

check_integrity() {
    echo -ne "\nRunning integrity check   "
    local integrityCheckPassed=true
    declare -a failedDirectories
    for sourcePath in "${sourcePaths[@]##*/}"; do
        spin
        cd "$backupRootDirectory" || exit
        if ! sha256sum --quiet -c "$backupRootDirectory/.glacier/digests/$sourcePath.sha256" \
        &> "$backupRootDirectory/.glacier/reports/$sourcePath.log"; then
            numberOfFailedFiles=$(grep -ci "FAILED" "$backupRootDirectory/.glacier/reports/$sourcePath.log")
            failedDirectories+=("$sourcePath: ${dim}$numberOfFailedFiles  ${normal}")
            integrityCheckPassed=false
        fi
    done
    echo -e "\nIntegrity check passed: $integrityCheckPassed"
    if [[ "$integrityCheckPassed" ]]; then
        for failedDirectory in "${failedDirectories[@]}"; do
            echo "Failed at: $failedDirectory "
        done
    fi
}

check_integrity_at_start_up() {
    clear -x
    find "$backupDrivePath" -mindepth 1 -maxdepth 1 -type d | cat -n
    read -rp "${bold}Select backup to run integrity check from: ${normal}" option
    backupRootDirectory=$(find "$backupDrivePath" -mindepth 1 -maxdepth 1 -type d | awk "FNR==$option")
    check_integrity
}

clean_reports() {
    echo
    read -rp "Clean reports? [Y/n] " options
    case "${options,,}" in
        y ) rm -rf "$backupRootDirectory/.glacier/reports"/*;;
        n ) exit;;
        * ) rm -rf "$backupRootDirectory/.glacier/reports"/*;;
    esac
}

while getopts ":hrd" flag; do
    case "${flag}" in
        h ) cat ~/Tools/scripts/glacier/documentation.txt;;
        r ) check_integrity_at_start_up && clean_reports;;
        d ) get_backup_description;;
        * ) echo -e "Unrecognized option\nTry \`glacier.sh -h\` for more information";;
    esac
done

[ -z "$*" ] && display_directories
