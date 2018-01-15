#!/usr/bin/env bash
sleep .2
while [[ -f result-building ]]; do top -n 1 ; sleep 5; done;
echo The waiting is over
sleep .4
