_zcomplete() {
  local CMD="$1"
  local CUR="$2"
  local IFS=$'\n'
  local ZCOMP=""
  if [[ "$(basename "$CMD")" == "zcomp" ]];then
    ZCOMP="$CMD"
  else
    ZCOMP="$(which zcomp 2> /dev/null)"
    if [[ "$?" != "0" ]]; then
      return $?;
    fi
  fi

  local CMDREPLY="$("$ZCOMP" "bash" "${COMP_CWORD}" "${COMP_WORDS[@]}")"
  local EXITCODE="$?"
  if [[ "$EXITCODE" != "0" ]]; then
    unset COMPREPLY
  else
    mapfile -t COMPREPLY < <( compgen -W "$CMDREPLY" -- "$cur")
  fi
}

complete -o default -o bashdefault -D -F _zcomplete
