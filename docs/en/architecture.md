# Architecture

Desired/received and reference samples enter FIFO and pack memories. A 12-tap complex FIR produces prediction Y from the current W, and `E=D-Y`. The matrix path computes P times the input vector, the denominator, reciprocal, gain K, twelve weight updates, and the P rank-1 update.

The matrix core uses a 150-cycle schedule. With packing and external event alignment, steady updates are 175 cycles apart; the accepted 1,000-update run contains one 208-cycle refill, giving `175:998;208:1`.

The verified mode requires `sel_fb1 == sel_fb2`. `reset_ready` exposes synchronized reset release. Eighteen synthesizable SRAM wrappers define the macro integration boundary; macro timing, physical views, and MBIST are not included.
