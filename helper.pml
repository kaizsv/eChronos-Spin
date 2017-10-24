#define NBUSERS 2
#define NBINTS 2
#define SVC 0
#define PendSV 1
#define USER0 (2 + NBINTS)
#define NONE 254
#define NBROUTS (2 + NBINTS + NBUSERS)
#define CHECKEND (2 + NBINTS - 1)

#define FOR_LOOP_U for (idx: 0 .. (NBUSERS - 1))
#define FOR_LOOP_I for (idx: 0 .. (NBINTS - 1))
#define FOR_LOOP_I_INALL for (idx: 2 .. (2 + NBINTS - 1))
#define FOR_LOOP_I_SCHED_INALL for (idx: 0 .. (2 + NBINTS - 1))
#define FOR_LOOP_ROUTS for (idx: 0 .. (NBROUTS - 1))

#define get_bit(b, word) (word & (1 << b))

byte EIT;
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

#define INT_PRE_1 assert(ATtop > 0 && _pid == AT)
#define INT_PRE_2 assert(ATtop > 0 && _pid == AT && PendSVReq)

#define CTXT_INV assert(PendSVReq || (E[0] == false && E[1] == false) \
                     || (2 <= AT && AT < USER0))
#define CTXT_SW_INV CTXT_INV; sched_policy_inv(retCtxtInv, nextT);\
                    assert(retCtxtInv)
#define CTXT_SW_LAST_INV CTXT_SW_INV;                             \
                         assert(ATtop > 0 && ATStack[ATtop-1] == nextT)
#define CTXT_SW_IRet_INV CTXT_INV; assert(ATtop > 0);             \
                         sched_policy_inv(retCtxtInv, ATStack[ATtop-1]);\
                         assert(retCtxtInv);

#define SVC_INV assert(AT != SVC                                  \
              || (PendSV != AT && PendSV != ATStack[0]            \
                  && PendSV != ATStack[1] && PendSV != ATStack[2] \
                  && PendSV != ATStack[3] && PendSV != ATStack[4] \
                  && PendSV != ATStack[5]))
#define PendSV_INV assert(PendSV == AT || PendSV == ATStack[0]    \
                  || PendSV == ATStack[1] || PendSV == ATStack[2] \
                  || PendSV == ATStack[3] || PendSV == ATStack[4] \
                  || PendSV == ATStack[5])
#define SCHED_PRE_1 assert(PendSV                                 \
                        || (E[0] == E_tmp[0] && E[1] == E_tmp[1]) \
                        || (2 <= AT && AT < USER0))
#define SCHED_PRE_2 assert(PendSV                                 \
                        || (E[0] == false && E[1] == false)       \
                        || (2 <= AT && AT < USER0))

#define USER_PRE assert(!(USER0 <= AT && AT < NBROUTS)            \
                    || (PendSVReq || (E[0] == false && E[1] == false)))
#define USER_INV USER_PRE; assert(!(AT == _pid && get_bit(PendSV, EIT)) || !PendSVReq)

/*inline handle_events_inv() {
    FOR_LOOP_I {
        assert(idx < NBUSERS);
        R[idx] = R[idx] | E[idx]
    }
    idx = 0
}*/

inline sched_policy_inv(ret, tar) {
    ret = false;
    FOR_LOOP_U {
        if
        :: R[idx] == true -> ret = (tar == (USER0 + idx)); break
        :: else -> skip
        fi
    }
    idx = 0
}

/*inline sched_inv(ret) {
    d_step {
        if
        :: (AT >= USER0 && AT < NBROUTS) && EIT[PendSV] && !PendSVReq ->
            handle_events_inv();
            sched_policy_inv(ret, AT)
        :: else -> ret = true
        fi
    }
}*/

inline hardware_init() {
    AT = USER0;
    FOR_LOOP_ROUTS {
        ATStack[idx] = NONE
    }
    idx = 0;
    FOR_LOOP_I_SCHED_INALL {
        set_bit(idx, EIT)
    }
    idx = 0
}

inline eChronos_init() {
    curUser = USER0;
    nextT = NONE;
    byte j;
    FOR_LOOP_U {
        R[idx] = true;
        for (j: 0 .. (NBROUTS - 1)) {
            contexts_ATStack[idx * NBROUTS + j] = NONE
        }
        j = 0;

        // contexts
        contexts_preempt[idx] = true;
        contexts_ATStack[idx * NBROUTS + 0] = (USER0 + idx);
        contexts_ATtop[idx] = 1
    }
    idx = 0
}

inline set_bit(b, word)
{
    word = word | (1 << b)
}

inline clear_bit(b, word)
{
    word = word & ~(1 << b)
}

