# Forgejo Borg Backup Script
A backup script template for self-hosted Forgejo instances, utilising Borg Backup, rsync and ntfy.

All of the following assumes you are running a docker instance of Forgejo on a Linux system, and are using the SQLite database implementation.

These set of scripts are primarily for those who have a self-hosted Forgejo instance, don't have a backup plan in place, love to tinker, and want to have a dedicated off-site backup implementation.
These are not scripts to download and directly run, these are more like templates. Download, read, edit, experiment.

If you're the only one using the instance (like myself), or there's a small team of people who are using it, these could be the backup scripts for you.

> [!WARNING]
> This script only works with Forgejo instances that use SQLite, and not MySQL or Postgres, and (as per the Forgejo documentation/recommendation) *this will shut down the server for backups*.

## Prerequisites
Using these scripts assumes you have a few things already in place.

This is not a step by step guide on how to set these systems and services up, but more what you should have prepared.

My main Forgejo server runs Ubuntu, but my remote servers are running a minimal build of Debian to keep them lean.


| Application | Usage                                      | Server   |
|-------------|--------------------------------------------|----------|
| tailscale   | Remote connection between servers          | **All**  |
| borg        | Main backup system                         | **All**  |
| rsync       | Copy the backup files to the remote server | **All**  |
| ntfy        | For status notifications                   | **Main** |

Make sure you have a non-root user account on all systems set up with `sudo` permissions.

On all systems, create a location the backups will live. For my setup, I've opted for `/var/borg`. Ensure you change ownership on it to your non-root user.

### Tailscale
Tailscale is a zero-trust connectivity platform (whatever the fuck that actually means) that allows you to make a device to device VPN.

Instead of exposing ports, adding complexity and creating potential security risks, we'll connect the server Forgejo is running on to the remote servers directly.

Add your servers (main and remotes), and make sure SSH is enabled for them in the Tailscale console.

**Make sure you have generated SSH keys for your primary user (non-root) on your main server, and the keys have been copied to the remote servers *using their Tailscale IP/FQDN*.**
Without doing this step, rsync will fail to copy because you haven't trusted the server's fingerprint.

> [!TIP]
> Also add your keys from your laptop or computer to the remote servers, in case you ever need to access it whenever you're physically near it.

Harden the remote servers by disabling password authentication, and disabling root logins. There's a few ssh hardening tutorials out there, just find one and follow the steps. But, for the love of god, [don't disable PAM](https://sshhole.com)

> [!IMPORTANT]
> While I've set up Tailscale for my deployment, Cloudflare's Zero Trust One Client Tunnel (please stop changing names) thing could work, but is currently untested.
> As long as it creates a private device-to-device network, they should be fine.

### Borg
This is the main star of the show, ~~Patrick Stewart~~ ~~Jean-Luc Picard~~ ~~Locutus of Borg~~ BorgBackup.

A little more leg work to get set up, but better than having dozens of large zip files, and it supports verification to make sure the data is still intact after backing up/sending over to the remote servers.

It's recommend to download the binary from the BorgBackup website, as Ubuntu has the (almost) most recent build, but Debian carries an older stable build (v1.4.0 as of writing).
Better to have consistency over convenience.

Initialise your backup with `borg init --encryption=repokey /path/to/backup/forgejo` on the main server. For me, the path would be `/var/borg/forgejo`.

Make a memorable passphrase, and keep note of it. Also make a backup of the encryption keys, and store them safely.

### rsync
Noting it down here, you might need to install rsync on the remote servers as it doesn't come installed on Debian in a minimal build.

### ntfy (optional)
To know how the backups are going, I have a self-hosted instance of ntfy running on my server stack, and any notifications are immediately pushed to my phone.
You don't have to self-host it, and can sign up for an account at [ntfy.sh](https://ntfy.sh)

Sending push notifications about the backup status isn't required, but highly recommend to know the health of the entire operation.

## Usage

### `backup.sh`
The backup flow is:

* Forgejo is safely shut down
* Borg creates a backup marked with today's date
* Forgejo is brought back online
* Borg prunes old backups, and compacts it
* Rsync then sends the backup folder to the remote servers

Rational behind this path is keeping Forgejo up as much as possible. If you were to create a local backup and for any remote servers through borg, there would be a time penalty.
Making a local backup, then copying that to the remote servers reduces that time penalty.

In the `backup.sh` script, make sure to populate the location in `BORG_REPO`, store the passphrase you created earlier in `BORG_PASSPHRASE`, the location of your Forgejo instance in `SOURCE_DIR`, and if you have opted in to doing push notifications through ntfy, the token, url, and topic of the ntfy instance you're using in `NTFY`.

If you're using multiple backup servers, populate the user and IP of the remote server's Tailscale IP/FQDN. Create more for however many servers you'll be syncing to, and append more rsync commands at the bottom of the script.

### `verify.sh`
This checks the integrity of the backups on the local and remote servers, using the `borg check --verify-data` command. On slower systems or very large backups, this can take some time to process.

> [!IMPORTANT]
> Though it can take time to verify the backups, it's highly recommended to keep `--verify-data` enabled as it ensures the data is cryptographically sound to what is expected.
> If removed, make sure to do a check with `--verify-data` at least once a month as a health check.

Like with the `backup.sh` script, put your `BORG_REPO` location, `BORG_PASSPHRASE`, the ntfy publishing URL, and the username and remote server's Tailscale IP/FQDN.

The script will send the full result of the `borg check` command as a notification, regardless if it was successful or it failed.

### Running them
Set up a cronjob for the root user to trigger them at a specific time.

It's recommended to run the backup daily, during periods of low or no activity (3am is a really good time for that!)

It's recommended to verify the integrity of the backups between once a week to once a fortnight. Ensure the verification is run well after the backup has been completed.

## Caveats

### Forgejo shutdown
As stated above, the Forgejo documentation highly recommends that Forgejo is shut down every time to process a backup. This is to ensure that there are no file or database writes while the backup occurs, potentially corrupting data.

To get around the system being taken off-line frequently, you can simply run the backup less frequently, but the risk of losing data goes up the longer between runs.

What's the correct answer? Whatever you're comfortable with.

## Todo

### Restore
Quite obviously, there's no restore script. Yet. It is still being written and tested, and the restore script will be added when completed.
