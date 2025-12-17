# SNESJITSkeleton (Swift + Metal + x86_64 JIT) — Phase-based build

This is a *compile-first* skeleton intended to keep the emulator **manageable** by splitting logic into many small Swift files (no folders needed).

> Target: macOS (Intel x86_64), single-core friendly design, Metal for video, optional x86_64 JIT for CPU hot paths.

---

## How to use this zip in Xcode

1. Create a new **macOS App** (SwiftUI) project in Xcode (any name).
2. Drag **all `.swift` files** from this zip into your Xcode project navigator (top level).  
   - When prompted: **Copy items if needed** ✅, and ensure your app target is checked.
3. Add the `Shaders.metal` file to the project as well.
4. Build & Run. You should see a window with a Metal-backed view rendering a simple test pattern.

This skeleton does *not* yet run commercial ROMs—Phase 1 focuses on structure + timing + rendering pipeline.

---

## Phases (we’ll implement one phase at a time)

### Phase 0 — Scaffolding (DONE in this skeleton)
- App + Metal swapchain
- Emulator core loop and time step
- Bus + memory map placeholders
- CPU/PPU/APU stubs wired together
- JIT infrastructure placeholder (executable memory + tiny assembler helpers)

### Phase 1 — CPU 65C816 Core (Interpreter first, JIT later)
- Implement 65C816 registers, flags, emulation/native modes
- Addressing modes + instruction decode
- Unit tests for instructions (micro-tests)
- Run small CPU test ROMs (or internal test program)

### Phase 2 — Memory Map + DMA/HDMA + Timers
- WRAM/ROM mapping (LoROM/HiROM)
- I/O registers
- DMA and HDMA
- NMI/IRQ timing hooks

### Phase 3 — PPU (picture)
- PPU registers
- Background rendering (Mode 0/1 first)
- Sprites (OAM), windowing, color math
- VBlank/NMI timing alignment

### Phase 4 — APU (sound)
- SPC700 + DSP (initially stub, then real)
- Audio buffering to CoreAudio

### Phase 5 — Accuracy + Performance
- Cycle accuracy options
- **CPU JIT** for hot blocks:
  - decode → IR → x86_64 emit
  - basic block cache with invalidation
  - fast-path for common ops
- Single-core scheduling: CPU/PPU/APU interleave in one thread deterministically

---

## Notes on the JIT design here
- We allocate executable pages with `mmap(PROT_READ|PROT_WRITE|PROT_EXEC)` (macOS Intel).
- The emitter in this skeleton is minimal and only meant as a starting point.
- In Phase 5 we’ll implement real block compilation and a fallback interpreter.

---

## Next step
Tell me **“Phase 1”** and I’ll start filling in the 65C816 interpreter (still split across lots of files).
