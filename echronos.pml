
// TODO: need to solve nondeterministic.
/* eChronos source code
   machine-stm32f4-discovery.kochab-system
   machine-stm32f4-discovery.kochab-sched-demo
*/
#define NBUSERS 2
#define NBINTS 2
#define SVC 0
#define PendSV 1
#define USER0 (2 + NBINTS)
#define NONE 254
#define NBROUTS (2 + NBINTS + NBUSERS)

#define SCHED_INV do :: atomic { sched_inv(retSchedInv); assert(retSchedInv); break; } od
#define AWAITS(p, C)                                     \
                    do                                   \
                    :: atomic {                          \
                            if                           \
                            :: (AT == p) -> C; break;    \
                            :: else -> skip;             \
                            fi;                          \
                       }                                 \
                    od;                                  \
                    SCHED_INV

#define SVC_NOW ATStack[ATtop] = AT; ATtop++; AT = SVC
#define PendSVREQUEST PendSVReq = true
#define PendSVENABLE EIT[PendSV] = true
#define PendSVDISABLE EIT[PendSV] = false

#define FOR_LOOP_U for (idx: 0 .. (NBUSERS - 1))
#define FOR_LOOP_I for (idx: 0 .. (NBINTS - 1))
#define FOR_LOOP_I_INALL for (idx: 2 .. (2 + NBINTS - 1))
#define FOR_LOOP_I_SCHED_INALL for (idx: 0 .. (2 + NBINTS - 1))
#define FOR_LOOP_ROUTS for (idx: 0 .. (NBROUTS - 1))

bool allRun;
bool EIT[2 + NBINTS];
bool PendSVReq;
pid AT, nextT;
pid ATStack[NBROUTS];
byte ATtop;
pid curUser;
bool contexts_preempt[NBUSERS];
pid contexts_ATStack[NBUSERS * NBROUTS];
byte contexts_ATtop[NBUSERS];
bool R[NBUSERS];
bool E[NBINTS], E_tmp[NBINTS];

mtype = {signal_send, block};
mtype userSyscall;

inline copy_E_tmp() {
    FOR_LOOP_I {
        E_tmp[idx] = E[idx];
    }
    idx = 0;
}

/* eChronos links interrupt handler to a user task.
   at rtos-kochab.c: 345
*/
//rtos-kochab.c: 718
// TODO: check preemption disable
// TODO: send signal
// TODO: update runnable task, right now is fine
inline handle_events() {
    printf("handle_events\n");
    FOR_LOOP_I {
        assert(idx < NBUSERS);
        R[idx] = R[idx] | E_tmp[idx];
    }
    idx = 0;
}

inline clear_E() {
    FOR_LOOP_I {
        E[idx] = E[idx] & !E_tmp[idx];
        E_tmp[idx] = false;
    }
    idx = 0;
}

// rtos-kochab.c: 475
inline sched_policy() {
    printf("sched_policy\n");
    FOR_LOOP_U {
        if
        :: R[idx] == true -> nextT = (USER0 + idx); break;
        :: else;
        fi;
    }
    idx = 0;
}

// rtos-kochab.c: 691
inline schedule(p) {
    printf("schedule\n");
    AWAITS(p, nextT = NONE);
    do
    :: nextT == NONE ->
        AWAITS(p, copy_E_tmp());
        AWAITS(p, handle_events());
        AWAITS(p, clear_E());
        AWAITS(p, sched_policy());
    :: else -> break;
    od;
}

inline save_context(cur, en) {
    assert(cur >= USER0 && cur != NONE);
    contexts_preempt[cur - USER0] = en;
    contexts_ATtop[cur - USER0] = ATtop;
    FOR_LOOP_ROUTS {
        contexts_ATStack[(cur - USER0) * NBROUTS + idx] = ATStack[idx];
    }
    idx = 0;
}

inline restore_context_ATStack(cur) {
    assert(cur >= USER0 && cur != NONE);
    ATtop = contexts_ATtop[cur - USER0];
    FOR_LOOP_ROUTS {
        ATStack[idx] = contexts_ATStack[(cur - USER0) * NBROUTS + idx];
    }
    idx = 0;
}

inline restore_context_preempt(cur) {
    assert(cur >= USER0 && cur != NONE);
    if
    :: contexts_preempt[cur - USER0] -> PendSVENABLE;
    :: !contexts_preempt[cur - USER0] -> PendSVDISABLE;
    fi;
}

// f: preempt-enable
inline context_switch(p, f) {
    printf("context_switch\n");
    AWAITS(p, save_context(curUser, f));
    AWAITS(p, curUser = nextT);
    AWAITS(p, restore_context_ATStack(curUser));
    AWAITS(p, restore_context_preempt(curUser));
}

inline inATStack(i, ret) {
    ret = false;
    for (idx: 0 .. ATtop - 1) {
        if
        :: ATStack[idx] == i -> ret = true; break;
        :: else;
        fi;
    }
    idx = 0;
}

inline interrupt_policy(i, tar, ret) {
    printf("interrupt_policy\n");
    ret = false;
    checkEnd = (2 + NBINTS - 1);
    if
    :: tar == SVC || tar == PendSV -> checkStart = 2;
    :: tar >= USER0 && tar < NBROUTS -> checkStart = 0;
    :: tar >= 2 && tar < (2+NBINTS) -> checkStart = tar;
    fi;
    for (idx: checkStart .. checkEnd) {
        if
        :: idx == i -> if
                       :: idx == tar -> skip;
                       :: else -> ret = true; break;
                       fi;
        :: else;
        fi;
    }
    idx = 0;
}

inline ITake(i) {
    do
    :: atomic {
        printf("ITake\n");
        inATStack(i, retInATStack);
        interrupt_policy(i, AT, retPolicy);
        if
        :: EIT[i] && i != AT && !retInATStack && retPolicy ->
            ATStack[ATtop] = AT; ATtop++; AT = i; break;
        :: else;
        fi;
       }
    od;
    SCHED_INV;
}

inline IRet(i) {
    printf("IRet\n");
    inATStack(PendSV, retInATStack);
    assert(ATtop > 0);
    interrupt_policy(PendSV, ATStack[ATtop-1], retPolicy);
    if
    :: PendSVReq && EIT[PendSV] && !retInATStack && retPolicy ->
        AT = PendSV; PendSVReq = false;
    :: else ->
        // assert ATtop > 0 before the if condition
        ATtop--; AT = ATStack[ATtop]; ATStack[ATtop] = NONE;
    fi;
}

inline handle_events_inv() {
    FOR_LOOP_I {
        assert(idx < NBUSERS);
        R[idx] = R[idx] | E[idx];
    }
    idx = 0;
}

inline sched_policy_inv(ret) {
    FOR_LOOP_U {
        if
        :: R[idx] == true -> ret = true; break;
        :: else;
        fi;
    }
    idx = 0;
}

inline sched_inv(ret) {
    ret = false;
    do
    :: atomic {
        if
        :: (AT >= USER0 && AT < NBROUTS) && EIT[PendSV] && !PendSVReq ->
            skip;
        :: else -> ret = true; break;
        fi;
        handle_events_inv();
        sched_policy_inv(ret);
    }
    od;
}

// ctxt-switch-preempt.s: 219
active proctype SVC_p() {
    bool retInATStack, retPolicy;
    pid checkStart, checkEnd;
    byte idx;
    bool retSchedInv;
    assert(_pid == SVC);
    (allRun);
start:
    schedule(_pid);
    context_switch(_pid, false);
    AWAITS(_pid, IRet(_pid));
    goto start;
}

// ctxt-switch-preempt.s: 250
active proctype PendSV_p() {
    bool retInATStack, retPolicy;
    pid checkStart, checkEnd;
    byte idx;
    bool retSchedInv;
    assert(_pid == PendSV);
    (allRun);
start:
    schedule(_pid);
    context_switch(_pid, true);
    AWAITS(_pid, IRet(_pid));
    goto start;
}

inline change_events() {
    printf("change_events\n");
    FOR_LOOP_I {
        if
        :: true -> E[idx] = true;
        //:: true -> skip;
        fi;
    }
    idx = 0;
}

active [NBINTS] proctype interrupt_p() {
    bool retInATStack, retPolicy;
    pid checkStart, checkEnd;
    byte idx;
    bool retSchedInv;
    assert(PendSV < _pid && _pid < (2 + NBINTS));
    (allRun);
start:
    ITake(_pid);
    AWAITS(_pid, change_events());
    AWAITS(_pid, PendSVREQUEST);
    AWAITS(_pid, IRet(_pid));
    goto start;
}

inline change_usersyscall() {
    if
    :: true -> userSyscall = signal_send;
    :: true -> userSyscall = block;
    fi;
}

active [NBUSERS] proctype user_p() {
    byte idx;
    bool retSchedInv;
    assert(USER0 <= _pid && _pid < NBROUTS);
    (allRun);
start:
    AWAITS(_pid, change_usersyscall());
    SCHED_INV;
    if
    :: userSyscall == signal_send ->
        AWAITS(_pid, PendSVDISABLE);
        // R remind no change
        AWAITS(_pid, PendSVREQUEST);
        AWAITS(_pid, PendSVENABLE);
        do
        :: PendSVReq -> AWAITS(_pid, skip);
        :: !PendSVReq -> AWAITS(_pid, break);
        od;
    :: userSyscall == block ->
        AWAITS(_pid, PendSVDISABLE);
        AWAITS(_pid, R[_pid-USER0] = false);
        AWAITS(_pid, SVC_NOW);
        AWAITS(_pid, PendSVENABLE);
        do
        :: PendSVReq -> AWAITS(_pid, skip);
        :: !PendSVReq -> AWAITS(_pid, break);
        od;
    fi;
    goto start;
}

inline PendSVTake_p() {
    do
    :: atomic {
        printf("PendSVTake_p\n");
        if
        :: !PendSVReq || !EIT[PendSV] || PendSV == AT -> break;
        :: else;
        fi;
        inATStack(PendSV, retInATStack);
        interrupt_policy(PendSV, AT, retPolicy);
        if
        :: !retInATStack && retPolicy ->
            ATStack[ATtop] = AT; ATtop++; AT = PendSV; PendSVReq = false;
        :: else;
        fi;
        break;
       }
    od;
}

init {
    byte idx;
    // initialize
    d_step {
        AT = USER0;
        curUser = USER0;
        nextT = NONE;
        FOR_LOOP_I_SCHED_INALL {
            EIT[idx] = true;
        }
        idx = 0;
        FOR_LOOP_ROUTS {
            ATStack[idx] = NONE;
        }
        idx = 0;
        byte j;
        FOR_LOOP_U {
            R[idx] = true;
            for (j: 0 .. NBROUTS - 1) {
                contexts_ATStack[idx * NBROUTS + j] = NONE;
            }
            j = 0;

            // contexts
            contexts_preempt[idx] = true;
            contexts_ATStack[idx * NBROUTS + 0] = (USER0 + idx);
            contexts_ATtop[idx] = 1;
        }
        idx = 0;
    }

    allRun = true;

    bool retInATStack, retPolicy;
    pid checkStart, checkEnd;
    bool retSchedInv;
end:
    do
    :: PendSVTake_p(); SCHED_INV;
    od;

}
