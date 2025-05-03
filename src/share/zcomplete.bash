_zcomplete() {
  local CMD="$1"
  local CUR="$2"
  local IFS='\n'

  local CMDREPLY="$("$CMD" "bash" "${COMP_CWORD}" "${COMP_WORDS[@]}")"
  mapfile -t COMPREPLY < <( compgen -W "$CMDREPLY" -- "$cur")
}

complete -F _zcomplete zcomp
