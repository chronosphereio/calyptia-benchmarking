# TAIL with TCP output scenario

## Description

This scenario creates a log file in the data folder.
Once the log processor is started it processes this pre-existing file.
The output of the log processor is sent to a TCP endpoint (in JSON format): by default this is another Fluent Bit instance with a TCP input.
The scenario is considered done once the configured scenario time has elapsed.

## Input

File, JSON

## Output

TCP, JSON
