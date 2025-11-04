#!/bin/bash

cat extensions.txt | xargs -L 1 cursor --install-extension
