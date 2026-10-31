# Architectural Blueprint: Implementing z/OS and CICS Support in the Neper Toolchain

This document provides the formal architectural specifications required to extend the **Neper** systems programming language and its direct-emitting compilation toolchain to support IBM z/OS and the CICS (Customer Information Control System) transaction processor engine. 

As a self-hosting language optimized for predictable, native execution without LLVM, a VM, or a garbage collector, Neper must interface directly with the low-level execution semantics of IBM's z/Architecture ISA and its proprietary Generalized Object File Format (GOFF).

---

## 1. Compiler Backend Modifications (z/Architecture Target)

Neper's direct emitter must bypass intermediate toolchains and emit native z/Architecture instructions. The backend target architecture (e.g., `s390x` or `zArch`) must enforce traditional mainframe register allocations and Language Environment (LE) software stacks.

### 1.1 Register Allocation Matrix

Unlike x86-64 and AArch64 hardware-defined stacks, z/Architecture uses 16 General Purpose Registers (GPRs) managed by software calling conventions. The Neper compiler backend must map its Abstract Intermediate Representation (AIR) to the following layout:

*   **GPR 1 (R1):** Parameter list address pointer. Every CICS statement compiled must construct arguments in contiguous memory blocks and assign R1 to point to this structure.
*   **GPR 13 (R13):** Dynamic Storage Area (DSA) pointer. This serves as the active stack frame pointer. Neper's stack frames must comply with the standard IBM Language Environment (LE) layout, providing 72-byte (31-bit) or 144-byte (64-bit) save areas.
*   **GPR 14 (R14):** Return address link register.
*   **GPR 15 (R15):** Program entry point address and function return status code.

### 1.2 Language Environment (LE) Linkage Compliance

Functions compiled for z/OS must generate an LE-compliant prologue and epilogue to ensure proper task isolation and prevent operating system abends within the CICS transaction region:

*   **Prologue:** Save caller registers into the area pointed to by R13, allocate a new stack frame (DSA), and chain the new frame's backward pointer to the previous frame.
*   **Epilogue:** Restore original caller registers, unchain the DSA, load the return status into R15, and branch back via R14.

---

## 2. Linker Integration: Implementing GOFF (Generalized Object File Format)

Neper features an integrated linker to avoid external tool dependencies. For z/OS execution, the linker backend must be expanded to output **GOFF records** instead of standard Windows PE or Linux ELF structures.

### 2.1 GOFF Record Specification

GOFF treats binaries as a sequence of logical, variable-length records (up to 256 bytes per record). The internal linker must assemble compiled modules using these 4 standard record blocks:

| GOFF Record Type | Purpose | Implementation Action for Neper Linker |
| :--- | :--- | :--- |
| **ESD (External Symbol Dictionary)** | Defines external references and entry points. | Maps Neper function names, public symbols, and external CICS stubs like `DFHELII`. |
| **TXT (Text)** | Contains raw compiled machine code bytes. | Stores the emitted z/Architecture binary instruction stream. |
| **RLD (Relocation Dictionary)** | Describes address constants requiring relocation. | Flags internal memory references that the z/OS program binder (`IEWBLINK`) must adjust when loading the binary into memory. |
| **END** | Terminate the object deck. | Signifies the end of the module and designates the executable entry point. |

### 2.2 Structural Linker Constraints

*   **Member Name Mangling:** Neper allows long names and explicit package boundaries. However, z/OS Load Modules and Partitioned Data Sets (PDS/PDSE) traditionally limit executable member names to **8 characters**. The Neper linker must implement a deterministic compression/hashing algorithm to truncate long Neper paths (e.g., `e.io.print` becomes `EIO#PRNT`).
*   **Target Output Matrix:** The cross-linker running on Windows must write out these GOFF records to a continuous byte-stream file, ready to be sent to z/OS UNIX System Services (USS) or a Partitioned Data Set Extended (PDSE).

---

## 3. Standard Library Porting Strategy

Neper contains an extensive standard library surface (`e.io`, `e.task`, `e.data`, etc.) designed to run uniformly across targets. To make it functional on a mainframe, critical low-level primitives must be adapted.

### 3.1 Character Set Translation (ASCII to EBCDIC)

Neper source files and internally handled strings are natively UTF-8 encoded. Because CICS screen maps, terminals, and sub-systems rely exclusively on EBCDIC, your compiler must perform a compile-time encoding step.
*   **Monomorphization Pass:** When lowering string literals to raw bytes, translate UTF-8/ASCII bytes into **IBM-1047 (EBCDIC)** hex equivalents. 

### 3.2 Adapting the Allocator (`e.mem`)

Neper relies on explicit arenas and stack usage instead of a global allocator or garbage collector.
*   **Standard Implementation:** Uses system calls like `mmap` or `VirtualAlloc`.
*   **z/OS CICS Adaptation:** Standard operating system memory requests disrupt task isolation in CICS. The z/OS port of Neper's arena initializer must wrap around the CICS memory engine:
    ```text
    EXEC CICS GETMAIN SET(pointer) FLENGTH(size)
    ```
*   Arena destruction must map directly to:
    ```text
    EXEC CICS FREEMAIN DATA(pointer)
    ```

### 3.3 Rewriting I/O Hooks (`e.io`)

Programs running inside a live CICS transaction region do not have standard access to `stdout` or `stderr`.
*   `io.print` calls must be context-swapped. Instead of printing to a terminal pipe, they must trigger an `EXEC CICS SEND TEXT` instruction sequence, write to a CICS Temporary Storage Queue (**TSQ**), or dump to a Transient Data Queue (**TDQ**).

---

## 4. Direct CICS Code Generation API (The `try` Integration)

Neper handles error states via a clean `(T, err)` multi-return architecture paired with the `try` operator. You can make CICS commands behave natively within Neper by mapping command block execution directly to this type system.

### 4.1 Emitting the CICS Execution Sequence

When a developer writes an inline CICS directive or uses a wrapper library, the compiler must output the binary structure required by the CICS interface engine (`DFHELII`).

```text
1. Allocate continuous memory block for Parameter Pointers.
2. Word 0 -> Point to CICS Function Block Descriptor (Defines command parameters).
3. Word 1 -> Point to Data Buffer.
4. Word 2 -> Point to Data Length Variable.
5. Set high-order bit of the last word pointer to 1 (End of list indicator).
6. Load the address of the pointer array into Register 1.
7. Call DFHELII: L 15, =V(DFHELII) followed by BASR 14, 15.
```

### 4.2 Mapping Response Codes to Neper Errors

CICS returns execution results inside fields named `RESP` and `RESP2` in the Exec Interface Block (EIB). 
*   **The Bridge:** Your runtime wrapper must inspect these fields immediately following the `BASR 14, 15` call. 
*   If `RESP` is not equal to `DFHRESP(NORMAL)`, your runtime must translate the specific mainframe condition code into a concrete instantiation of Neper's `err` type. This seamlessly enables constructs like `try cics.send(...)` to clear or propagate errors using standard Neper syntax.
