#!/usr/bin/env bash

if [[ $EUID -ne 0 ]]; then
   echo "This script must be executed with sudo."
   exit 1
fi

echo "Do you have an account list?  [y/N] "

read inputFlag
echo "Starting Scrubber..."
printf "%s\n"
if [[ "${inputFlag,,}" != "y" ]]; then
    
    allUsers="/etc/passwd"
    accessableUsers=()
    declare -A user

    wheelMembers=$(getent group wheel | cut -d: -f4)
    sudoMembers=$(getent group sudo 2>/dev/null | cut -d: -f4)
    rootMembers=$(getent group root | cut -d: -f4)

    if [ ! -f "$allUsers" ]; then
        echo "Error: It might be time for poker with Red Team ;-;, File Not Found || $allUsers"
        exit 1
    fi

    echo "Located Users"
    printf "%s\n" "----------"

    # Tries to eliminate all service accounts and anything with the nologin directory
    while IFS=: read -r username password uid gid gecos home shell; do
        if (( uid >= 1 && uid < 1000 )); then
            continue
        fi

        noLoginFlag=false
        if [[ "$shell" == */nologin ]]; then
            noLoginFlag=true
            echo -e "\033[0;41mThis User Has An Unaccessible Shell (Please Verify)\033[0m"
        fi

        privilege="normal"

        if (( uid == 0 )); then
            privilege="root"
            echo -e "\033[0;41mThis User Has Root Access (Please Verify)\033[0m"

        elif [[ ",$wheelMembers," == *",$username,"* ]]; then
            privilege="wheel"
            echo -e "\033[0;33mThis User Has Sudo Access (Please Verify)\033[0m"

        elif [[ ",$sudoMembers," == *",$username,"* ]]; then
            privilege="sudo"
            echo -e "\033[0;33mThis User Has Sudo Access (Please Verify)\033[0m"

        elif [[ ",$rootMembers," == *",$username,"* ]]; then
            privilege="root"
            echo -e "\033[0;41mThis User Has Root Access (Please Verify)\033[0m"
        fi

        accessibleUsers+=("$username")

        user["$username,uid"]="$uid"
        user["$username,gid"]="$gid"
        user["$username,home"]="$home"
        user["$username,shell"]="$shell"
        user["$username,nologin"]="$noLoginFlag"
        user["$username,privilege"]="$privilege"

        printf "User: %s\n" "$username"
        printf "  UID: %s\n" "$uid"
        printf "  GID: %s\n" "$gid"
        printf "  Home: %s\n" "$home"
        printf "  Shell: %s\n" "$shell"
        printf "  Privilege: %s\n\n" "$privilege"

    done < "$allUsers"

    printf "%s\n" "----------"

    echo "Would you like to alter any account privledges? [y/N]"

    user_exists() {
        local search="$1"
        for user in "${accessibleUsers[@]}"; do
            if [[ "$user" == "$search" ]]; then
                return 0
            fi
        done
        return 1
    }

    read inputFlag
    if [[ "${inputFlag,,}" == "y" ]]; then
        while true; do
            echo "Which user would you like to edit? (or type 'exit')"
            read targetUser

            if [[ "$targetUser" == "exit" ]]; then
                break
            fi

            if ! user_exists "$targetUser"; then
                echo "User not found in accessible user list."
                continue
            fi

            currentPriv="${user["$targetUser,privilege"]}"

            echo "Current privilege: $currentPriv"
            echo "1) Grant sudo"
            echo "2) Remove sudo"
            echo "3) Cancel"
            read choice

            case "$choice" in
                1)
                    usermod -aG sudo "$targetUser"
                    user["$targetUser,privilege"]="sudo access"
                    echo "Sudo granted."
                    ;;
                2)
                    gpasswd -d "$targetUser" sudo
                    user["$targetUser,privilege"]="normal"
                    echo "Sudo removed."
                    ;;
                3)
                    echo "Cancelled."
                    ;;
                *)
                    echo "Invalid option."
                    ;;
            esac
        done
    fi

    echo "Would you like to copy an account list? [Y/n]"

    read inputFlag
    echo ""
    if [[ "${inputFlag,,}" == "y" ]]; then
        for username in "${accessibleUsers[@]}"; do
            printf "%s %s %s %s\n" \
            "$username" \
            "${user["$username,uid"]}" \
            "${user["$username,privilege"]}" \
            "${user["$username,home"]}"
        done
    fi
else
    echo "What is the file path to the account list?"
    while true; do
            read filePath
            echo "Are you sure it is correct? No going back after this! [Y/n]"
            read targetUser
            
            if [[ "${targetUser,,}" == "y" ]]; then
                break
            fi
    done

    if [[ -f "$filePath" ]]; then
        echo "processing given file"

        while IFS=" " read -r uname userId privilege home; do
            echo "Processing: $uname"
            
            if id "$uname" &>/dev/null; then
                echo "User $uname exists"
            else
                echo -e "\033[0;41mCreating user $uname\033[0m"
                useradd -m -u "$userId" -d "$home" "$uname"
                echo "$uname:reinstated123!" | chpasswd
            fi

            if [[ "$privilege" == "wheel" ]]; then
                echo -e "\033[0;33mAdding $uname to wheel group\033[0m"
                usermod -aG wheel "$uname"
            else
                echo "Removing $uname from wheel group"
                gpasswd -d "$uname" wheel 2>/dev/null
            fi

            currentHome=$(getent passwd "$uname" | cut -d: -f6)

            if [[ "$currentHome" != "$home" ]]; then
                echo "Updating home directory for $uname"
                usermod -d "$home" -m "$uname"
            fi
            
        done < "$filePath"
    else
        echo "Error, path not found"
    fi

fi

echo ""
echo "Your users have been successfully scrubbed!"