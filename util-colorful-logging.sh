#!/bin/bash

function defineColours(){
    export header="\x1b[0;33m"
    export err="\x1b[48;5;1m"
    export info="\x1b[0;32m"
    export highlight="\x1b[0;36m"
    export reset="\e[0m"
}

function displayErr(){ printf "\n$err %s $reset\n\n" "$*"; }
function displayInfo(){ printf "\n$info %s $reset\n" "$*";}
function displayHeader(){  printf "\n\n$header ---------------------- %s ------------- $reset\n" "$*" ;}
function highlight(){  printf "$highlight \t %s $reset\n" "$*" ;}