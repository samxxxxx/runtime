# Licensed to the .NET Foundation under one or more agreements.
# The .NET Foundation licenses this file to you under the MIT license.

.intel_syntax noprefix
#include "unixasmmacros.inc"
#include "asmconstants.h"

#define real4 dword
#define real8 qword

#
#    file: profile.cpp
#    typedef struct _PROFILE_PLATFORM_SPECIFIC_DATA
#    {
#        FunctionID *functionId; # function ID comes in the r11 register
#        void       *rbp;
#        void       *probersp;
#        void       *ip;
#        void       *profiledRsp;
#        UINT64      rax;
#        LPVOID      hiddenArg;
#        UINT64      flt0;
#        UINT64      flt1;
#        UINT64      flt2;
#        UINT64      flt3;
#        UINT64      flt4;
#        UINT64      flt5;
#        UINT64      flt6;
#        UINT64      flt7;
#        UINT64      rdi;
#        UINT64      rsi;
#        UINT64      rdx;
#        UINT64      rcx;
#        UINT64      r8;
#        UINT64      r9;
#        UINT32      flags;
#        UINT64      buffer[PROFILE_PLATFORM_SPECIFIC_DATA_BUFFER_SIZE];
#    } PROFILE_PLATFORM_SPECIFIC_DATA, *PPROFILE_PLATFORM_SPECIFIC_DATA;

# On linux arguments can be passed in non-sequential registers. Integer arguments are
# passed in sequential integer registers and floating point registers are passed in
# sequential floating point registers. This presents a problem when we go to pass the
# struct argument as a COR_PRF_FUNCTION_ARGUMENT_RANGE which expects the arguments are
# in one contiguous range. This space is a scratch space that the ArgIterator can use
# to copy the structs to so they are sequential.
.equ SIZEOF_PROFILE_STRUCT_BUFFER, 0x8*16

# Space for register spilling
.equ SIZEOF_PROFILE_PLATFORM_SPECIFIC_DATA, 0x8*22 + SIZEOF_PROFILE_STRUCT_BUFFER

# Pad the frame size by 0x8 so when the xmm0 and xmm1 register store/restore happens
# we can align to 16 and be guaranteed to not exceed the frame size
.equ STACK_FUDGE_FACTOR, 0x8

# SIZEOF_STACK_FRAME is how many bytes we reserve in our ELT helpers below
# There are three components, the first is space for profiler platform specific
# data struct that we spill the general purpose registers to, then space to
# spill xmm0 and xmm1, then finally 8 bytes of padding to ensure that the xmm
# register reads/writes are aligned on 16 bytes.
.equ SIZEOF_STACK_FRAME, SIZEOF_PROFILE_PLATFORM_SPECIFIC_DATA + STACK_FUDGE_FACTOR

.equ PROFILE_ENTER, 0x1
.equ PROFILE_LEAVE, 0x2
.equ PROFILE_TAILCALL, 0x4

# ***********************************************************
#   NOTE:
#
#   Register preservation scheme:
#
#       Preserved:
#           - all non-volatile registers
#           - rax, rcx, rdx, r8, r9
#           - xmm0, xmm1
#
#       Not Preserved:
#           - floating point argument registers (xmm2-3)
#           - volatile integer registers (r10, r11)
#           - volatile floating point registers (xmm4-5)
#           - upper halves of ymm registers on AVX (which are volatile)
#
# ***********************************************************

# EXTERN_C void ProfileEnterNaked(FunctionIDOrClientID functionIDOrClientID, size_t profiledRsp);
# <NOTE>
#
# </NOTE>
NESTED_ENTRY ProfileEnterNaked, _TEXT, NoHandler
  #       Upon entry :
  #           r14 = clientInfo
  #           r15 = profiledRsp

  push_nonvol_reg         rax

  lea                     rax, [rsp + 0x10]    # caller rsp
  mov                     r10, [rax - 0x8]     # return address

  push_argument_register  rdx
  alloc_stack             SIZEOF_STACK_FRAME

  # correctness of return value in structure doesn't matter for enter probe

  # setup ProfilePlatformSpecificData structure
  xor                     r11, r11 # nullify r11
  mov                     [rsp + 0x0], r11    # r11 is null     -- struct functionId field
  save_reg_postrsp        rbp, 0x8             #                 -- struct rbp field
  mov                     [rsp + 0x10], rax    # caller rsp      -- struct probeRsp field
  mov                     [rsp + 0x18], r10    # return address  -- struct ip field
  mov                     [rsp + 0x20], r15    #                 -- struct profiledRsp field
  mov                     [rsp + 0x28], r11    # return value    -- struct rax field
  mov                     [rsp + 0x30], r11    # r11 is null     -- struct hiddenArg field
  movsd                   real8 ptr [rsp + 0x38], xmm0    #      -- struct flt0 field
  movsd                   real8 ptr [rsp + 0x40], xmm1    #      -- struct flt1 field
  movsd                   real8 ptr [rsp + 0x48], xmm2    #      -- struct flt2 field
  movsd                   real8 ptr [rsp + 0x50], xmm3    #      -- struct flt3 field
  movsd                   real8 ptr [rsp + 0x58], xmm4    #      -- struct flt4 field
  movsd                   real8 ptr [rsp + 0x60], xmm5    #      -- struct flt5 field
  movsd                   real8 ptr [rsp + 0x68], xmm6    #      -- struct flt6 field
  movsd                   real8 ptr [rsp + 0x70], xmm7    #      -- struct flt7 field
  mov                     [rsp + 0x78], rdi               #      -- struct rdi field
  mov                     [rsp + 0x80], rsi               #      -- struct rsi field
  mov                     [rsp + 0x88], rdx               #      -- struct rdx field
  mov                     [rsp + 0x90], rcx               #      -- struct rcx field
  mov                     [rsp + 0x98], r8                #      -- struct r8 field
  mov                     [rsp + 0xa0], r9                #      -- struct r9 field
  mov                     r10, 0x1 # PROFILE_ENTER
  mov                     [rsp + 0xa8], r10d              #      -- struct flags field

  END_PROLOGUE

  # rdi already contains the clientInfo
  mov                     rdi, r14
  lea                     rsi, [rsp + 0x0]
  call                    C_FUNC(ProfileEnter)

  # restore fp return registers
  movsd                   xmm0, real8 ptr [rsp + 0x38]    #      -- struct flt0 field
  movsd                   xmm1, real8 ptr [rsp + 0x40]    #      -- struct flt1 field
  movsd                   xmm2, real8 ptr [rsp + 0x48]    #      -- struct flt2 field
  movsd                   xmm3, real8 ptr [rsp + 0x50]    #      -- struct flt3 field
  movsd                   xmm4, real8 ptr [rsp + 0x58]    #      -- struct flt4 field
  movsd                   xmm5, real8 ptr [rsp + 0x60]    #      -- struct flt5 field
  movsd                   xmm6, real8 ptr [rsp + 0x68]    #      -- struct flt6 field
  movsd                   xmm7, real8 ptr [rsp + 0x70]    #      -- struct flt7 field

  # restore arg registers
  mov                     rdi, [rsp + 0x78]
  mov                     rsi, [rsp + 0x80]
  mov                     rdx, [rsp + 0x88]
  mov                     rcx, [rsp + 0x90]
  mov                     r8, [rsp + 0x98]
  mov                     r9, [rsp + 0xa0]

  # begin epilogue
  free_stack              SIZEOF_STACK_FRAME
  pop_argument_register   rdx

  pop_nonvol_reg          rax

  ret
NESTED_END ProfileEnterNaked, _TEXT

# EXTERN_C void ProfileLeaveNaked(FunctionIDOrClientID functionIDOrClientID, size_t profiledRsp);
# <NOTE>
#
# </NOTE>
NESTED_ENTRY ProfileLeaveNaked, _TEXT, NoHandler
#       Upon entry :
#           rdi = clientInfo
#           rsi = profiledRsp

  push_nonvol_reg         rbx

  lea                     rbx, [rsp + 0x10]    # caller rsp
  mov                     r10, [rbx - 0x8]     # return address

  # rdx should be saved here because it can be used for returning struct values
  push_argument_register  rdx
  alloc_stack             SIZEOF_STACK_FRAME

  # correctness of argument registers in structure doesn't matter for leave probe

  # setup ProfilePlatformSpecificData structure
  xor                     r11, r11  # nullify r11
  mov                     [rsp +  0x0], r11    # r11 is null     -- struct functionId field
  save_reg_postrsp        rbp, 0x8             #                 -- struct rbp field
  mov                     [rsp + 0x10], rbx    # caller rsp      -- struct probeRsp field
  mov                     [rsp + 0x18], r10    # return address  -- struct ip field
  mov                     [rsp + 0x20], rsi    #                 -- struct profiledRsp field
  mov                     [rsp + 0x28], rax    # return value    -- struct rax field
  mov                     [rsp + 0x30], r11    # r11 is null     -- struct hiddenArg field
  movsd                   real8 ptr [rsp + 0x38], xmm0    #      -- struct flt0 field
  movsd                   real8 ptr [rsp + 0x40], xmm1    #      -- struct flt1 field
  movsd                   real8 ptr [rsp + 0x48], xmm2    #      -- struct flt2 field
  movsd                   real8 ptr [rsp + 0x50], xmm3    #      -- struct flt3 field
  movsd                   real8 ptr [rsp + 0x58], xmm4    #      -- struct flt4 field
  movsd                   real8 ptr [rsp + 0x60], xmm5    #      -- struct flt5 field
  movsd                   real8 ptr [rsp + 0x68], xmm6    #      -- struct flt6 field
  movsd                   real8 ptr [rsp + 0x70], xmm7    #      -- struct flt7 field
  mov                     [rsp + 0x78], r11     #                -- struct rdi field
  mov                     [rsp + 0x80], r11     #                -- struct rsi field
  mov                     [rsp + 0x88], rdx     #                -- struct rdx field
  mov                     [rsp + 0x90], r11     #                -- struct rcx field
  mov                     [rsp + 0x98], r11     #                -- struct r8 field
  mov                     [rsp + 0xa0], r11    #                -- struct r9 field
  mov                     r10, 0x2  # PROFILE_LEAVE
  mov                     [rsp + 0xa8], r10d   # flags           -- struct flags field

  END_PROLOGUE

  # rdi already contains the clientInfo
  lea                     rsi, [rsp + 0x0]
  call                    C_FUNC(ProfileLeave)

  # restore fp return registers
  movsd                   xmm0, real8 ptr [rsp + 0x38]    #      -- struct flt0 field
  movsd                   xmm1, real8 ptr [rsp + 0x40]    #      -- struct flt1 field
  movsd                   xmm2, real8 ptr [rsp + 0x48]    #      -- struct flt2 field
  movsd                   xmm3, real8 ptr [rsp + 0x50]    #      -- struct flt3 field
  movsd                   xmm4, real8 ptr [rsp + 0x58]    #      -- struct flt4 field
  movsd                   xmm5, real8 ptr [rsp + 0x60]    #      -- struct flt5 field
  movsd                   xmm6, real8 ptr [rsp + 0x68]    #      -- struct flt6 field
  movsd                   xmm7, real8 ptr [rsp + 0x70]    #      -- struct flt7 field

  # restore int return register
  mov                     rax, [rsp + 0x28]

  # begin epilogue
  free_stack              SIZEOF_STACK_FRAME
  pop_argument_register   rdx

  pop_nonvol_reg          rbx

  ret
NESTED_END ProfileLeaveNaked, _TEXT

# EXTERN_C void ProfileTailcallNaked(FunctionIDOrClientID functionIDOrClientID, size_t profiledRsp);
# <NOTE>
#
# </NOTE>
NESTED_ENTRY ProfileTailcallNaked, _TEXT, NoHandler
#       Upon entry :
#           rdi = clientInfo
#           rsi = profiledRsp

  push_nonvol_reg         rbx

  lea                     rbx, [rsp + 0x10]    # caller rsp
  mov                     r10, [rbx - 0x8]     # return address

  # rdx should be saved here because it can be used for returning struct values
  push_argument_register  rdx
  alloc_stack             SIZEOF_STACK_FRAME

  # correctness of argument registers in structure doesn't matter for tailcall probe

  # setup ProfilePlatformSpecificData structure
  xor                     r11, r11  # nullify r11
  mov                     [rsp +  0x0], r11    # r11 is null     -- struct functionId field
  save_reg_postrsp        rbp, 0x8             #                 -- struct rbp field
  mov                     [rsp + 0x10], rbx    # caller rsp      -- struct probeRsp field
  mov                     [rsp + 0x18], r10    # return address  -- struct ip field
  mov                     [rsp + 0x20], rsi    #                 -- struct profiledRsp field
  mov                     [rsp + 0x28], rax    # return value    -- struct rax field
  mov                     [rsp + 0x30], r11    # r11 is null     -- struct hiddenArg field
  movsd                   real8 ptr [rsp + 0x38], xmm0    #      -- struct flt0 field
  movsd                   real8 ptr [rsp + 0x40], xmm1    #      -- struct flt1 field
  movsd                   real8 ptr [rsp + 0x48], xmm2    #      -- struct flt2 field
  movsd                   real8 ptr [rsp + 0x50], xmm3    #      -- struct flt3 field
  movsd                   real8 ptr [rsp + 0x58], xmm4    #      -- struct flt4 field
  movsd                   real8 ptr [rsp + 0x60], xmm5    #      -- struct flt5 field
  movsd                   real8 ptr [rsp + 0x68], xmm6    #      -- struct flt6 field
  movsd                   real8 ptr [rsp + 0x70], xmm7    #      -- struct flt7 field
  mov                     [rsp + 0x78], r11     #                -- struct rdi field
  mov                     [rsp + 0x80], r11     #                -- struct rsi field
  mov                     [rsp + 0x88], rdx     #                -- struct rdx field
  mov                     [rsp + 0x90], r11     #                -- struct rcx field
  mov                     [rsp + 0x98], r11     #                -- struct r8 field
  mov                     [rsp + 0xa0], r11     #                -- struct r9 field
  mov                     r10, 0x2  # PROFILE_LEAVE
  mov                     [rsp + 0xa8], r10d   # flags           -- struct flags field

  END_PROLOGUE

  # rdi already contains the clientInfo
  lea                     rsi, [rsp + 0x0]
  call                    C_FUNC(ProfileTailcall)

  # restore fp return registers
  movsd                   xmm0, real8 ptr [rsp + 0x38]    #      -- struct flt0 field
  movsd                   xmm1, real8 ptr [rsp + 0x40]    #      -- struct flt1 field
  movsd                   xmm2, real8 ptr [rsp + 0x48]    #      -- struct flt2 field
  movsd                   xmm3, real8 ptr [rsp + 0x50]    #      -- struct flt3 field
  movsd                   xmm4, real8 ptr [rsp + 0x58]    #      -- struct flt4 field
  movsd                   xmm5, real8 ptr [rsp + 0x60]    #      -- struct flt5 field
  movsd                   xmm6, real8 ptr [rsp + 0x68]    #      -- struct flt6 field
  movsd                   xmm7, real8 ptr [rsp + 0x70]    #      -- struct flt7 field

  # restore int return register
  mov                     rax, [rsp + 0x28]

  # begin epilogue
  free_stack              SIZEOF_STACK_FRAME
  pop_argument_register   rdx

  pop_nonvol_reg          rbx

  ret
NESTED_END ProfileTailcallNaked, _TEXT

#ifdef TARGET_OSX
# EXTERN_C void* GetThreadVarsAddress()
# <NOTE>
# Helper to calculate the address of relevant __thread_vars section that holds the address of symbol tlv_get_address for thread
# local `t_ThreadStatics`. The address is updated by the linker, which we retrieve here. In JIT code, this address is called
# to retrieve the address of the thread local.
# </NOTE>
LEAF_ENTRY GetThreadVarsAddress, _TEXT
        mov     rdi,    _t_ThreadStatics@TLVP[rip]
        ret
LEAF_END GetThreadVarsAddress, _TEXT
// ------------------------------------------------------------------
#endif // TARGET_OSX

#ifndef TARGET_OSX
# EXTERN_C void* GetTlsIndexObjectDescOffset();

# <NOTE>
# Helper to calculate the offset of native thread local variable `t_ThreadStatics`. The offset has to be found at runtime
# once linker does its relocation and fixup of thread locals. The runtime gets the address of this function, so
# it can walk through the instruction bytes to retrieve the offset embedded by the linker and calculate the
# final offset that should be passed to __tls_get_addr() in order to calculate the address of `t_ThreadStatics` for
# the current thread. Here, we have to call `__tls_get_addr()`, because if the linker tries to find the code pattern
# of "lea t_ThreadStatics@TLSGD", followed by `call __tls_get_addr()`. Without adding the call, the linker complains.
# We never have to call this method directly, and hence there is a `int 3` at the end.
# </NOTE>

LEAF_ENTRY GetTlsIndexObjectDescOffset, _TEXT
# On The `lea` instruction has a data16 prefix and the call instruction has two data16 (0x66) prefixes and one rex64 prefix.
# This is so the total size of lea+call to be 16, suitable for link-time optimization.

        .byte 0x66
        lea     rdi,    t_ThreadStatics@TLSGD[rip]   # instruction where offset is embedded by the linker during compilation
        .byte 0x66
        .byte 0x66
        .byte 0x48 # rex.W prefix for padding
        call    EXTERNAL_C_FUNC(__tls_get_addr)                      # dummy call to have linker see the code pattern to replace the offset
        int 3
LEAF_END GetTlsIndexObjectDescOffset, _TEXT
#endif
