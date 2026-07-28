#!/bin/bash
# ======================================================
#  COMPAQ CD PLAYER - reproductor de CD de audio para antiX
#  Requiere: mplayer, cd-discid (opcional pero recomendado)
#    sudo apt install mplayer cd-discid
# ======================================================

DEVICE="/dev/sr0"
FIFO="/tmp/cdplayer_fifo"
LOGFILE="/tmp/cdplayer_mplayer.log"
SHUFFLE=0
MPLAYER_PID=""

cleanup() {
    [ -n "$MPLAYER_PID" ] && kill "$MPLAYER_PID" 2>/dev/null
    exec 3>&- 2>/dev/null
    rm -f "$FIFO"
    clear
    exit 0
}
trap cleanup EXIT INT TERM

# --- comprobaciones previas ---
if ! command -v mplayer >/dev/null 2>&1; then
    echo "Falta 'mplayer'. Instalalo con: sudo apt install mplayer"
    exit 1
fi

[ -p "$FIFO" ] || mkfifo "$FIFO"

start_player() {
    : > "$LOGFILE"
    # abrimos la fifo en el descriptor 3 para que no se cierre entre comandos
    exec 3<>"$FIFO"
    mplayer -slave -quiet -input file="$FIFO" "cdda://1-99:$DEVICE" >"$LOGFILE" 2>&1 &
    MPLAYER_PID=$!
}

send_cmd() {
    echo "$1" >&3 2>/dev/null
}

get_status() {
    if command -v cd-discid >/dev/null 2>&1; then
        if cd-discid "$DEVICE" >/dev/null 2>&1; then
            echo "CD detectado"
        else
            echo "Esperando CD..."
        fi
    else
        # sin cd-discid, al menos verificamos que el dispositivo exista
        [ -e "$DEVICE" ] && echo "Unidad presente (instala cd-discid para detectar disco)" || echo "Sin unidad"
    fi
}

get_track_info() {
    # mplayer va escribiendo esto en el log al cambiar de pista
    grep -a "Track" "$LOGFILE" 2>/dev/null | tail -1
}

toggle_shuffle() {
    if [ "$SHUFFLE" -eq 0 ]; then
        SHUFFLE=1
    else
        SHUFFLE=0
    fi
    if [ "$SHUFFLE" -eq 1 ]; then
        # salto a una pista aleatoria entre 1 y 20 (mplayer ignora si no existe)
        send_cmd "pt_step $(( (RANDOM % 10) + 1 ))"
    fi
}

start_player

while true; do
    clear
    echo "======================================"
    echo "         COMPAQ CD PLAYER"
    echo "======================================"
    echo
    echo "Unidad  : $DEVICE"
    echo "Estado  : $(get_status)"
    echo "Shuffle : $([ "$SHUFFLE" -eq 1 ] && echo ON || echo OFF)"
    echo
    TRACK=$(get_track_info)
    [ -n "$TRACK" ] && echo "$TRACK"
    echo
    echo "F7 Anterior"
    echo "F8 Pausa"
    echo "F9 Siguiente"
    echo "F10 Shuffle"
    echo
    echo "Q Salir"

    # lee una tecla, esperando hasta 1s (para refrescar la pantalla igual que antes)
    key=""
    read -rsn1 -t1 key
    if [[ "$key" == $'\e' ]]; then
        read -rsn2 -t0.1 rest
        key+="$rest"
    fi

    case "$key" in
        $'\e[18~') send_cmd "pt_step -1" ;;   # F7 = pista anterior
        $'\e[19~') send_cmd "pause" ;;        # F8 = pausa/play
        $'\e[20~') send_cmd "pt_step 1" ;;    # F9 = pista siguiente
        $'\e[21~') toggle_shuffle ;;          # F10 = shuffle on/off
        q|Q) cleanup ;;
    esac

    # si el proceso de mplayer murió (p.ej. se sacó el CD), lo relanzamos
    if ! kill -0 "$MPLAYER_PID" 2>/dev/null; then
        exec 3>&- 2>/dev/null
        start_player
    fi
done
