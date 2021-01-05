Capslock::Ctrl
Ctrl::Capslock

global ShiftActivated := 0

ToggleShift()
{
    global ShiftActivated
    if (ShiftActivated = 1)
    {
        ShiftActivated := 0
        Send {Shift up}
    }
    else
    {
        ShiftActivated := 1
        Send {Shift down}
    }
}

; 기본 방향키
!h:: Send {Left}
!j:: Send {Down}
!k:: Send {Up}
!l:: Send {Right}

!+h:: Send +{Left}
!+j:: Send +{Down}
!+k:: Send +{Up}
!+l:: Send +{Right}

; 단어 단위
!w:: Send ^{Right}
!b:: Send ^{Left} ; vsc 충돌 주의
!+w:: Send ^+{Right}
!+b:: Send ^+{Left}

; 행에서 이동
!+6:: Send {Home}
!+4:: Send {End}}

; 페이지 단위
!+[:: Send {PgUp}
!+]:: Send {PgDn}

; 선택
!v:: ToggleShift()
!+v:: ToggleShift()
