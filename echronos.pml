
/* eChronos source code
   machine-stm32f4-discovery.kochab-system
   machine-stm32f4-discovery.kochab-sched-demo
*/
#include "helper.pml"

/*#define AT_in_U (AT >= USER0 && AT < (NBROUTS))
#define E_all_false (E[0] == false && E[1] == false)

#define schedule_inv_premise (AT_in_U && get_bit(PendSV, EIT) && !PendSVReq)
#define schedule_inv_policy (E_all_false && ((R[0] == true && AT == 4) || (R[1] == true && AT == 5)))

ltl schedule_inv { [] (schedule_inv_premise -> schedule_inv_policy) }*/

#define AWAITS(p, C) atomic { (AT == p); C }

#define SVC_NOW d_step { ATStack[ATtop] = AT; ATtop++; AT = SVC }
#define PendSVREQUEST d_step { PendSVReq = true }
#define PendSVENABLE d_step { set_bit(PendSV, EIT) }
#define PendSVDISABLE d_step { clear_bit(PendSV, EIT) }

bool allRun;
mtype = {signal_send, block};

inline copy_E_tmp() {
    FOR_LOOP_I {
        E_tmp[idx] = E[idx]
    }
    idx = 0
}

/* eChronos links interrupt handler to a user task.
   at rtos-kochab.c: 345
*/
//rtos-kochab.c: 718
// TODO: check preemption disable
// TODO: send signal
// TODO: update runnable task, right now is fine
inline handle_events() {
    FOR_LOOP_I {
        assert(idx < NBUSERS);
        R[idx] = R[idx] | E_tmp[idx]
    }
    idx = 0
}

inline clear_E() {
    FOR_LOOP_I {
        E[idx] = E[idx] & !E_tmp[idx];
        E_tmp[idx] = false
    }
    idx = 0
}

// rtos-kochab.c: 475
inline sched_policy() {
    FOR_LOOP_U {
        if
        :: R[idx] == true -> nextT = (USER0 + idx); break
        :: else -> skip
        fi
    }
    idx = 0
}

inline save_context(cur, en) {
    assert(cur >= USER0 && cur != NONE);
    contexts_preempt[cur - USER0] = en;
    contexts_ATtop[cur - USER0] = ATtop;
    FOR_LOOP_ROUTS {
        contexts_ATStack[(cur - USER0) * NBROUTS + idx] = ATStack[idx]
    }
    idx = 0
}

inline restore_ctxt_ATStack(cur) {
    assert(cur >= USER0 && cur != NONE);
    ATtop = contexts_ATtop[cur - USER0];
    FOR_LOOP_ROUTS {
        ATStack[idx] = contexts_ATStack[(cur - USER0) * NBROUTS + idx]
    }
    idx = 0
}

inline restore_ctxt_preempt(cur) {
    assert(cur >= USER0 && cur != NONE);
    if
    :: contexts_preempt[cur - USER0] -> PendSVENABLE
    :: !contexts_preempt[cur - USER0] -> PendSVDISABLE
    fi
}

inline inATStack(i, ret) {
    d_step {
        ret = false;
        for (idx: 0 .. ATtop - 1) {
            if
            :: ATStack[idx] == i -> ret = true; break
            :: else -> skip
            fi;
        }
        idx = 0;
    }
}

inline interrupt_policy(i, tar, ret) {
    d_step {
        ret = false;
        if
        :: tar == i -> skip // can not be self
        :: (tar == SVC || tar == PendSV) && ATtop > 1 -> skip
        :: else ->
            if
            :: tar == SVC || tar == PendSV -> checkStart = 2
            :: tar >= USER0 && tar < NBROUTS -> checkStart = 0
            :: tar >= 2 && tar < (2+NBINTS) -> checkStart = tar
            fi
            for (idx: checkStart .. CHECKEND) {
                if
                :: idx == i -> ret = true; break
                :: else -> skip
                fi;
            }
            idx = 0
        fi
    }
}

inline ITake(i) {
    do
    :: atomic {
            inATStack(i, retInATStack);
            interrupt_policy(i, AT, retPolicy);
            if
            :: get_bit(i, EIT) && !retInATStack && retPolicy ->
                ATStack[ATtop] = AT;
                ATtop++;
                AT = i;
                break
            :: else -> skip
            fi
       }
    od
}

inline IRet(i) {
    inATStack(PendSV, retInATStack);
    assert(ATtop > 0);
    interrupt_policy(PendSV, ATStack[ATtop - 1], retPolicy);
    if
    :: PendSVReq && get_bit(PendSV, EIT) && !retInATStack && retPolicy ->
        AT = PendSV; PendSVReq = false
    :: else ->
        assert(ATtop > 0);
        ATtop--; AT = ATStack[ATtop]; ATStack[ATtop] = NONE
    fi;
}

// ctxt-switch-preempt.s: 219
active proctype SVC_p() {
    bool retInATStack, retPolicy;
    bool retCtxtInv;
    pid checkStart;
    byte idx;
    assert(_pid == SVC);
    (allRun);
endSVC_p:
    /* schedule
       rtos-kochab.c: 691
    */
    AWAITS(_pid, SVC_INV; nextT = NONE);
    do
    :: nextT == NONE ->
            AWAITS(_pid, SVC_INV; copy_E_tmp());
            AWAITS(_pid, SVC_INV; SCHED_PRE_1; handle_events());
            AWAITS(_pid, SVC_INV; SCHED_PRE_1; clear_E());
            AWAITS(_pid, SVC_INV; SCHED_PRE_2; sched_policy())
    :: else -> break
    od;

    /* context-switch */
    AWAITS(_pid, SVC_INV; CTXT_SW_INV; save_context(curUser, false));
    AWAITS(_pid, SVC_INV; CTXT_SW_INV; curUser = nextT);
    AWAITS(_pid, SVC_INV; CTXT_SW_INV; restore_ctxt_ATStack(curUser));
    AWAITS(_pid, SVC_INV; CTXT_SW_LAST_INV; restore_ctxt_preempt(curUser));

    AWAITS(_pid, SVC_INV; CTXT_SW_IRet_INV; IRet(_pid));
    goto endSVC_p
}

// ctxt-switch-preempt.s: 250
active proctype PendSV_p() {
    bool retInATStack, retPolicy;
    bool retCtxtInv;
    pid checkStart;
    byte idx;
    assert(_pid == PendSV);
    (allRun);
endPendSV_p:
    /* schedule
       rtos-kochab.c: 691
    */
    AWAITS(_pid, PendSV_INV; nextT = NONE);
    do
    :: nextT == NONE ->
            AWAITS(_pid, PendSV_INV; copy_E_tmp());
            AWAITS(_pid, PendSV_INV; SCHED_PRE_1; handle_events());
            AWAITS(_pid, PendSV_INV; SCHED_PRE_1; clear_E());
            AWAITS(_pid, PendSV_INV; SCHED_PRE_2; sched_policy())
    :: else -> break
    od;

    /* context-switch */
    AWAITS(_pid, PendSV_INV; CTXT_SW_INV; save_context(curUser, true));
    AWAITS(_pid, PendSV_INV; CTXT_SW_INV; curUser = nextT);
    AWAITS(_pid, PendSV_INV; CTXT_SW_INV; restore_ctxt_ATStack(curUser));
    AWAITS(_pid, PendSV_INV; CTXT_SW_LAST_INV; restore_ctxt_preempt(curUser));

    AWAITS(_pid, PendSV_INV; CTXT_SW_IRet_INV; IRet(_pid));
    goto endPendSV_p
}

// TODO: non-deterministic
inline change_events() {
    FOR_LOOP_I {
        if
        :: true -> E[idx] = true
        :: true 
        fi
    }
    idx = 0
}

active [NBINTS] proctype interrupt_p() {
    bool retInATStack, retPolicy;
    pid checkStart;
    byte idx;
    assert(PendSV < _pid && _pid < (2 + NBINTS));
    (allRun);
endInterrupt_p:
    ITake(_pid);
    AWAITS(_pid, INT_PRE_1; change_events());
    AWAITS(_pid, INT_PRE_1; PendSVREQUEST);
    AWAITS(_pid, INT_PRE_2; IRet(_pid));
    goto endInterrupt_p
}

inline change_usersyscall() {
    if
    :: true -> userSyscall = signal_send
    :: true -> userSyscall = block
    fi
}

active [NBUSERS] proctype user_p() {
    byte idx;
    mtype userSyscall;
    assert(USER0 <= _pid && _pid < NBROUTS);
    (allRun);
endUser_p:
    AWAITS(_pid, USER_INV; change_usersyscall());
    if
    :: userSyscall == signal_send ->
        // ghostU -> syscall
        AWAITS(_pid, USER_INV; PendSVDISABLE);
        // R remind no change
        AWAITS(_pid, PendSVREQUEST);
        AWAITS(_pid, assert(PendSVReq); PendSVENABLE);
        // ghostU -> user
        do
        :: PendSVReq -> AWAITS(_pid, skip)
        :: else -> break
        od
    :: userSyscall == block ->
        // ghostU -> syscall
        AWAITS(_pid, USER_INV; PendSVDISABLE);
        AWAITS(_pid, R[_pid-USER0] = false);
        AWAITS(_pid, SVC_NOW);               // ghostU -> yield
        AWAITS(_pid, USER_INV; PendSVENABLE);
        // ghostU -> user
        do
        :: PendSVReq -> AWAITS(_pid, skip)
        :: else -> break
        od
    fi;
    goto endUser_p
}

inline PendSVTake_p() {
    do
    :: atomic {
            inATStack(PendSV, retInATStack);
            interrupt_policy(PendSV, AT, retPolicy);
            if
            :: PendSVReq && get_bit(PendSV, EIT) && !retInATStack && retPolicy ->
                ATStack[ATtop] = AT;
                ATtop++;
                AT = PendSV;
                PendSVReq = false;
                break
            :: else -> skip
            fi
       }
    od
}

init {
    byte idx;
    // initialize
    d_step {
        hardware_init();
        eChronos_init()
    };

    allRun = true;

    bool retInATStack, retPolicy;
    pid checkStart;
endPendSVTake_p:
    PendSVTake_p();
    goto endPendSVTake_p

}
