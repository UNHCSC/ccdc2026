# UScrubber

UScrubber (User Scrubber) is a tool designed to simplify the modification of users in a linux environment. It contains the following functionalities:

1. Detect user accounts
2. Modify sudo priviledges of users
3. Create a backup of users
4. Restore the users from a backup

Uscrubber performs these tasks with the aid of a user to ensure correct assumptions, it does provide error/warnings to assist the user in decision making. However, this tool IS NOT perfect. It cannot see service accounts (on purpose) and relies on the user.


## How to perform actions with UScrubber

When starting the shell you will be prompted with:
- Do you have an account list (a backup of users to restore)
    - yes = Go to restore user process
    - no = Go to modify user process


### Modify User Process

This will initally give a list of all the users with their
- Username
- UID
- GID
- Home location
- Login Shell Type
- Priviledge  (only checks for sudo and root) 

afterwards, you have the ability to choose if you want to modify a user or, if everything looks good pass to the next step.

If you chose to modify a user you will be prompted with what user to change (username) and what priviledge they should have. Anything else must be done mannually either in the backup or by manual oversight.

Finally, after the users were modified you are prompted with a do you want an account list option. which
- prints out your backup of the users in the terminal. This must be copied and pasted into a text document on your own device. (for red team security reasons [can be changed])


### Restore user Process

This will give you a way to use an account list. (See Modify User Process for more details)  Which will:
- restore lost accounts with a new default password
- Modifies all accounts to a previous state in the account lsit

IT DOES NOT
- remove new accounts (use the modify user feature)

The format for the account list is the
- Username
- UID
- Priviledge
- Home Directory

Nothing else is considered. We can easily change this though to include something like the previous password.


## Other Notes / Improvements

- Can alter functionalty, this is currently the first prototype
- Tried taking into account red team activity, program is quite simple because of it.