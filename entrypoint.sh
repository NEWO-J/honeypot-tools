#!/bin/bash
hostname dart-prod-07
ssh-keygen -A
exec /usr/sbin/sshd -D
