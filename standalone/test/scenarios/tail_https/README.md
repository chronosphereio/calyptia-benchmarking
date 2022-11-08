# TAIL with HTTPS output scenario

## Description

This scenario creates a log file in the data folder.
Once the log processor is started it processes this pre-existing file.
The output of the log processor is sent to an HTTPS endpoint: <https://github.com/calyptia/https-benchmark-server>
The scenario is considered done once the configured scenario time has elapsed.

## Input

File, JSON

## Output

HTTPS
