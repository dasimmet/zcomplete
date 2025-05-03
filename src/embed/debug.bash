_zcomplete() {
  local CMD="$1"
  local CUR="$2"
  shift 1
  local ALL="$*"
  
  echo ""
  echo "ZCOMPLETE:"
  echo "COMPREPLY:" "${COMPREPLY[@]}"
  echo "COMP_CWORD:" "${COMP_CWORD}"
  echo "COMP_WORDS:" "${COMP_WORDS[@]}"
  echo "CMD: $CMD"
  echo "CUR: $CUR"
  echo "ALL: $ALL"
  echo "CALL:" "$CMD" "bash" "${COMP_CWORD}" "${COMP_WORDS[@]}"
  "$CMD" "bash" "${COMP_CWORD}" "${COMP_WORDS[@]}"
}

complete -F _zcomplete zcomp
 