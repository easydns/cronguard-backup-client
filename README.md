# Cronguard Client by Cronly


## Table of Contents

- [Introduction](#introduction)
- [Features](#features)
- [Installation](#installation)
- [Configuration](#configuration)
- [License](#license)
- [Support](#support)
- [Changelog](#changelog)
- [Contact Us](#contact)

## Introduction

This is the Cronly backup client endpoint.

It connects to your account on [Cronly.app](https://cronly.app) in order to store backups of your local crontabs whenever they change.

You will require an API key for your Cronly account, however you can install that after you run the _./install.sh_ script by modifying the _api.conf_ file in _/etc/cronguard_ directory (or wherever you specified on installation).

## Features

- **Automatic snapshots**

Every time a user on the local system updates their crontab, a snapshot of the new one is sent to the Cronly server for backup. 

The previous version of the crontab would be accessible as the second-most-recent snapshot.

- **Secure by default**

Common command line switches that preface passwords, which are normally in crontabs as cleartext, are redacted before being sent to the server.

You can modify these patterns in the _patterns.txt_ file in your configuration directory.

- **Command line client**

You can view which client servers and backups are stored as snapshotes within Cronly by use the _./cronguard-cli.sh_ command line client. 

See the _--help_ option to view usage.

- **Monitored**

It would not do to have a process that backs up your crontabs, that runs out of crontab, fail and not be aware of it.

Cronly is a cron job monitor (among other things), so each backup suite comes with a cron job monitor included. 

You should also monitor the backup job itself using a Job Monitor from the Cronly.app side - every backup bundles with a free backup job monitor which you can access via the [backups page](https://cronly.app/backups) for a given server.

_The monitor token must be installed after the first backup is created_ which you then add to *cronguard.conf*

That way if the process stops working, you'll be notified about it.

- ** Intrusion Detection **

As of version 1.0.1-beta, cronguard will now extract the commands and scripts that are called out of crontab, and maintain a local database of their checksums similar to how it tracks individual crontabs.

If any of those scripts or commands are altered, it will send an alert via the notifications set up via your [triggers](https://cronly.app/triggers)


## Installation

Simply run the _./install.sh_ script as root.

You can view the checksum for the client on the [Cronly downloads page](https://cronly.app/downloads)

### Prerequisites

You will need certain items installed in order for Cronly / cronguard to work:

- a headless browser like _curl_ or _wget_
- an md5 checksum utility
- _jq_ json parser

The installation script will check for these and let you know if you need to install something.

### Steps

Provide step-by-step instructions to install your project.

1. run "_sudo ./install.sh_" and follow the prompts
2. add the _monitor token_ to _cronguard.conf_ after the first backup is snapped and you create it from the Cronly.app side
3. add your API key to _api.conf_ if you didn't have that handy at the time
4. if you didn't allow the install script to add the client to your root crontab, do that now:

```
# cronly.app backup crontabs
*/5 * * * * /usr/local/sbin/cronguard.sh > /dev/null
```

In either case remember to set up your cron job monitor on the Cronly side as well.

## Configuration

Edit _patterns.conf_ if you want to change or add password patterns or any other senstive data you want to be redacted before being snapshotted. 

Add your API key to _api.conf_

Add your monitor token to _cronguard.conf_

## License

This project is licensed under the Apache License, Version 2.0. See the [LICENSE](LICENSE) file for more details.

## Support

Cronly users can support via [support](https://cronly.app/support) in your Cronly dashboard.

If you find an issue with the client, please enter an issue via [the repository](https://github.com/easydns/cronguard-backup-client)

## Changelog

### [1.0.1-beta] - 2024-08-02

#### Added
- Cronguard script monitoring and alerts for altered commands
- Addition of $SCRIPTS_DB to store checksums of commands run from crontab
- Added call to $ALERTS_ENDPOINT to send notifications on changes detected
- Added ./install.sh will now prompt and create backup server on Cronly.app side if user has the API key

#### Changed
- cronly.sh and cronly-cli.sh changed to cronguard.sh and cronguard-cli.sh

### [1.0.0-beta] - 2024-06-18

#### Added
- Initial beta release of the cronly-backup-client.
- Automated backup functionality.
- Integration with Cronly.app service.

#### Changed
- N/A

#### Fixed
- N/A

## Contact

Email any questions / concerns or business development or commercial licensing inquiries to Mark Jeftovic <markjr@easydns.com>

