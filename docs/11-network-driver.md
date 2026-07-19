# 11 · Network Driver (1536B + Shim Layer + 14B MAC DMA)

**Plan section**: §十一
**Key decisions**: D25, D60, D79, D96
**Status**: Frozen; Shim Layer default ON

---

## Overview

The network driver stack is a 3-layer SG-DMA architecture: (1) **14 B MAC DMA pool** (D79) holds Ethernet headers separately from RpcUnit payloads, (2) **1536 B NetworkFrame** (D57/D60) carries the L3+ payload, and (3) **Shim Layer** (D96) transparently adapts 1536 B ↔ 1500 B MTU for commercial switches that don't support Jumbo Frames. The Shim Layer is **default ON** and can be disabled at build time for known-Jumbo-Frame environments.

## Three-layer network stack

```
┌──── NIC hardware (SG-DMA 3 descriptors) ────┐
│ Descriptor 0: 14 B MAC header (D79)         │
│ Descriptor 1: 1536 B NetworkFrame payload   │
│ Descriptor 2: optional 4 B FCS (CRC)        │
└─────────────────────────────────────────────┘
                ↓
┌──── Shim Layer (D96, default ON) ───────────┐
│ if 1536B ≤ 1458B payload: 1 IP packet       │
│ if 1536B > 1458B payload: split to ≤ 1500B  │
│   ↳ Shim header: 8B (magic + seq + total)   │
│   ↳ Standard IP fragmentation semantics     │
└─────────────────────────────────────────────┘
                ↓
┌──── BlockPool RpcUnit (D29/D57) ─────────────┐
│ NetworkFrame (1536B) → RpcUnit (1536B)      │
│   ↳ Same physical layout (D57 three-layer)  │
│   ↳ Zero-copy cast (D3)                     │
└─────────────────────────────────────────────┘
```

## D60: 14B MAC external to 1536B

```zig
pub const MacHeader = extern struct {
    dst: [6]u8,
    src: [6]u8,
    ethertype: u16,    // 0x0800 = IPv4, 0x86DD = IPv6
};
comptime {
    std.debug.assert(@sizeOf(MacHeader) == 14);  // D60 hard constraint
}
```

The 14 B MAC is **never** part of the 1536 B RpcUnit. The NIC SG-DMA descriptor ring has 3 slots per frame: MAC header, payload (1536 B), optional FCS. This lets the driver use one descriptor per layer for clean zero-copy.

## D79: 14B MAC DMA pool

```zig
pub const MacDmaPool = struct {
    base: [*]align(64) u8,     // cache-line aligned
    size: usize,                // 256 × 14B = 3584B
    used: [256]AtomicBool,
};

pub fn mac_alloc() ?*MacHeader { ... }
pub fn mac_free(mac: *MacHeader) void { ... }
```

Why a separate pool? So the MAC header can be modified (e.g., for routing) without re-encoding the RpcUnit payload. The pool is **not** part of BlockPool; it's an adjacent 4KB page after NodePool.

## D96: Shim Layer (1536B ↔ 1500B MTU)

```rust
// D110 R31 fix: SHIM_PAYLOAD_MAX = 1464 = 1500 (MTU) - 20 (IP) - 8 (UDP) - 8 (shim)
// 旧值 1458 错把 MTU 当 L2 (含 14B MAC), 实为 L3 (仅 IP).
const SHIM_PAYLOAD_MAX: usize = 1464;  // D110 修正
const _: () = {
    assert!(SHIM_PAYLOAD_MAX + 20 + 8 <= 1500, "D110: total packet > MTU");
    assert!(SHIM_PAYLOAD_MAX + 8 <= 1472, "D110: UDP payload > 1472B ceiling");
};
```

## D108: Shim Layer L3 协议族参数化 (Q24 R31 fix)

**Status**: **RATIFIED** (Q24 → D108, R31).

D96 / D110 hardcodes IPv4 L3 header = 20B. Server Profile with `-Denable_ipv6=true` would emit `1464 + 40 + 8 + 8 = 1520 > 1500` MTU → IP fragmentation → Shim `shim_offset` field crosses slice boundary → reassemble fails. D108 parameterizes `SHIM_PAYLOAD_MAX` by `-Dip_family=v4|v6` at compile time, gated by D86 `_Static_assert` pattern.

```rust
// D108 R31 fix: 按 L3 协议族派生 SHIM_PAYLOAD_MAX, 杜绝 1520B 溢出
const IPV4_HDR_SIZE: usize = 20;
const IPV6_HDR_SIZE: usize = 40;
const UDP_HDR_SIZE: usize = 8;
const SHIM_HDR_SIZE: usize = 8;

// build.zig -Dip_family=v4|v6  (default v4)
const L3_HDR_SIZE: usize = if cfg!(ip_family = "v6") {
    IPV6_HDR_SIZE
} else {
    IPV4_HDR_SIZE
};

pub const SHIM_PAYLOAD_MAX: usize = 1500 - L3_HDR_SIZE - UDP_HDR_SIZE - SHIM_HDR_SIZE;
// IPv4 → 1464; IPv6 → 1444; 编译期单点真相

// D86 / D108 静态闸门: 双重保证 IP 包永远 ≤ 1500 MTU
const _: () = {
    assert!(SHIM_PAYLOAD_MAX + L3_HDR_SIZE + UDP_HDR_SIZE + SHIM_HDR_SIZE <= 1500,
            "D108: total IP packet must fit MTU=1500");
    assert!(SHIM_PAYLOAD_MAX <= UDP_MAX_PAYLOAD,  // 65507
            "D108: SHIM_PAYLOAD_MAX within UDP ceiling");
};

// 旧硬编码 IPv4 路径仅在 v4 模式下保留
#[cfg(ip_family = "v4")]
const _: () = assert!(SHIM_PAYLOAD_MAX == 1464, "D108: IPv4 SHIM_PAYLOAD_MAX must be 1464");
#[cfg(ip_family = "v6")]
const _: () = assert!(SHIM_PAYLOAD_MAX == 1444, "D108: IPv6 SHIM_PAYLOAD_MAX must be 1444");
```

**build.zig 新选项**:

```zig
pub const IpFamily = enum { v4, v6 };

pub const build_options = struct {
    ip_family: IpFamily = .v4,   // Embedded default v4
    sched: SchedKind = .rr,
    enable_page_aggregation: bool = false,
    enable_shim: bool = true,
    num_harts: u8 = 1,
    d107_enabled: bool = false,
    // ...
};
```

**Profile 对比**:

| Profile | `ip_family` | `L3_HDR_SIZE` | `SHIM_PAYLOAD_MAX` | 1536B frame 切片数 |
|---------|-------------|---------------|--------------------|---------------------|
| Embedded (default) | v4 | 20 | **1464** | 1 (no slice) or 2 |
| Server IPv4 | v4 | 20 | **1464** | 1 or 2 |
| Server IPv6 (R31 new) | v6 | 40 | **1444** | 1 or 2 |

**Cost / Benefit**:

| Dimension | D96/D110 (R30, IPv4-only) | D108 (R31, parameterized) |
|-----------|---------------------------|----------------------------|
| IPv4 性能 | 1464 字节/片 | 不变 1464 字节/片 |
| IPv6 路径 | ❌ 1520B 溢出 (Q24 GAP) | ✓ 1444 字节/片 |
| 编译期闸门 | 1 个 `assert!` | 4 个 `assert!` (单点真相) |
| ABI 影响 | 无 | `network_frame_t` 加 `ip_family: u8` 字段, 1536B 不变 |

**ABI 扩展** (D74 + D108 协同):

```rust
// D108: NetworkFrame 头部加 ip_family 字段, size 仍 1536B
#[repr(C, align(64))]
pub struct network_frame_t {
    pub header: frame_header_t,    // 8B
    pub ip_family: u8,             // 1B  (D108 NEW: 1=v4, 2=v6)
    pub _reserved0: [7]u8,         // 7B  (align padding)
    pub payload: [u8; 1520],       // 1520B (D57 1536 - 8 header - 8 reserved)
}

const _: () = assert!(core::mem::size_of::<network_frame_t>() == 1536, "D74");
```

---

## D131 增补 (R38 Q46, 勘误后): SHIM_PAYLOAD_MAX per-(L3, L4) 单公式派生 + l4_proto 字段冻结

> **回链**: 本节为 R38 审计新增 D131 提案, 与 D108 Shim Layer 协同, 解决 SHIM_PAYLOAD_MAX 仅覆盖 UDP 的 L4 协议盲区。

### 问题与动机

D108 现状只覆盖 UDP over IPv4 (1464B) 和 UDP over IPv6 (1444B)。**未覆盖 TCP / ICMP / GRE / VXLAN**:

| L4 协议 | 真实 L4 hdr | IPv4 包体 (含 IP + L4) | vs D108=1464 | 失效 |
|---------|--------------|------------------------|---------------|------|
| TCP | 20B | 20+20+1464 = 1504B > 1500 | **overshoot → 分片** |
| ICMP | 8B | 20+8+1464 = 1492B < 1500 | under-fill, OK |
| GRE | 4B | 20+4+1464 = 1488B < 1500 | under-fill, 浪费 12B |
| VXLAN | 50B | 20+50+1464 = 1534B > 1500 | **overshoot → 分片** |

**失效方向澄清**:
- **overshoot**: SHIM > 真实 L4 → 包体 > MTU → IP 分片 (D96 立法死敌)
- **under-fill**: SHIM < 真实 L4 → 包体 < MTU → 带宽浪费 (可接受)

D108 同时犯两种错: TCP/VXLAN overshoot 触发分片, GRE under-fill 浪费带宽。

### D131 立法

1. **单公式派生 (D131 落地约束 ①)**: SHIM_PAYLOAD_MAX 由 `1500 - L3 - L4 - SHIM` 单公式 comptime 派生, 严禁手写字面量。枚举只定义各协议头尺寸, 派生结果一字面量不许出现。
2. **l4_proto 字段冻结 (D131 落地约束 ②)**: Phase 0 接受 per-build 单 L4 (`-Dl4_proto`), 但在 `network_frame_t` 的 reserved 字节中**现在就冻结 `l4_proto: u8` 字段**, 作为 Phase 1+ 运行时多 L4 的演化钩子。

```zig
// build_options.zig (D131 单公式派生, 严禁手写字面量)
pub const L3Proto = enum { v4, v6 };
pub const L4Proto = enum { udp, tcp, icmp, gre, vxlan };

pub const L3_HDR_SIZE: u32 = switch (build_options.l3_proto) {
    .v4 => 20, .v6 => 40,
};
pub const L4_HDR_SIZE: u32 = switch (build_options.l4_proto) {
    .udp   => 8,
    .tcp   => 20,
    .icmp  => 8,
    .gre   => 4,
    .vxlan => 8 + 14 + 20,
};
pub const SHIM_HDR_SIZE: u32 = 8;

pub fn shim_payload_max(l3: L3Proto, l4: L4Proto) u32 {
    return 1500 - l3_hdr(l3) - l4_hdr(l4) - SHIM_HDR_SIZE;
}
fn l3_hdr(l: L3Proto) u32 { return switch (l) { .v4 => 20, .v6 => 40 }; }
fn l4_hdr(l: L4Proto) u32 { return switch (l) {
    .udp => 8, .tcp => 20, .icmp => 8, .gre => 4, .vxlan => 42,
}; }

comptime {
    const combos = [_]struct { l3: L3Proto, l4: L4Proto }{
        .{ .l3 = .v4, .l4 = .udp }, .{ .l3 = .v4, .l4 = .tcp },
        .{ .l3 = .v4, .l4 = .icmp }, .{ .l3 = .v4, .l4 = .gre }, .{ .l3 = .v4, .l4 = .vxlan },
        .{ .l3 = .v6, .l4 = .udp }, .{ .l3 = .v6, .l4 = .tcp },
        .{ .l3 = .v6, .l4 = .icmp }, .{ .l3 = .v6, .l4 = .vxlan },
    };
    inline for (combos) |c| {
        const p = shim_payload_max(c.l3, c.l4);
        if (p > 1500) @compileError("D131 FAIL");
        if (p + L3_HDR_SIZE + L4_HDR_SIZE + SHIM_HDR_SIZE != 1500) {
            @compileError("D131 FAIL: 单公式派生不一致");
        }
    }
}
```

```rust
// D131 l4_proto 字段冻结 (Phase 1+ 运行时多 L4 钩子)
#[repr(C, align(64))]
pub struct network_frame_t {
    pub header: frame_header_t,        // 8B
    pub ip_family: u8,                 // 1B  D108: 1=v4, 2=v6
    pub l4_proto: u8,                  // 1B  D131: 17=UDP, 6=TCP, 1=ICMP, 47=GRE
    pub _reserved0: [6]u8,             // 6B  (原 7B 改 6B, 留位给 l4_proto)
    pub payload: [u8; 1520],           // 1520B
}
const _: () = assert!(core::mem::size_of::<network_frame_t>() == 1536, "D74+D131");
const _: () = assert!(core::mem::offset_of!(network_frame_t, l4_proto) == 9, "D131 offset freeze");
```

### 传染面

- `13-build-pipeline.md` 新增 `make test-shim-l4-matrix` (9 组合 roundtrip, 期望值由公式算, 禁字面量)
- `02-memory-topology.md` § BlockPool 1536B 不变性 + D131 派生表
- `15-phase0-mvp.md` T1.13 升级为 D131 + 新增 T1.21 (L4 profile 单测)
- `20-documentation-gate.md` **新增禁词**: "SHIM 仅覆盖 UDP" / "L4 协议无关假设" / "SHIM_PAYLOAD_MAX 手写字面量"

### 元规则校验

- 手册: RFC 9293 (TCP) / RFC 792 (ICMPv4) / RFC 4443 (ICMPv6) / RFC 2784 (GRE) / RFC 7348 (VXLAN) / RFC 8200 (IPv6 ext)
- 失效方向: overshoot = IP 分片 (D96 死敌), under-fill = 带宽浪费 (可接受)
- 场景矩阵 (4 格): TCP overshoot / VXLAN overshoot / GRE under-fill / ICMP ok

**Verification**:

```bash
# 旧 R30 测试 (IPv4)
make test-jumbo-on    # 1464B payload, 1500B total → OK
make test-jumbo-off   # 1536B direct → OK

# R31 新增 (IPv6)
make test-shim-v6     # 1444B payload, 1500B total → OK
make test-shim-v6-reassemble  # 1536B frame 切成 2 片, reassemble 端 byte-identical
```

#[repr(C, align(4))]
pub struct shim_header_t {
    pub shim_magic: u16,    // 0xCAFE
    pub shim_seq: u16,      // 0..shim_total-1
    pub shim_total: u16,    // total slice count
    pub shim_offset: u16,   // byte offset in original payload
}

// P2-3 + D5/D103: shim_tx_split 改用固定 ShimTxBuffer (BlockPool-backed),
// 不分配 Vec, 不返回 Result (改返 i32 sys_error_t; 见 P2-2 错误码恒负立法).
// MAX_SHIM_SLICES = ceil(1536 / SHIM_PAYLOAD_MAX) + 1 = 2 (D131 per-(L3,L4)).
pub const MAX_SHIM_SLICES: usize = 2;

#[repr(C)]
pub struct ShimTxBuffer {
    pub packets: [IpPacket; MAX_SHIM_SLICES], // BlockPool-backed, 静态池
    pub count: u8,
}

/// Tx: 1536B frame → caller-provided ShimTxBuffer (固定切片), 返 i32 (error_code)
pub fn shim_tx_split(frame: &NetworkFrame, out: &mut ShimTxBuffer) -> i32 {
    let payload = &frame.payload;
    out.count = 0;
    if payload.len() <= SHIM_PAYLOAD_MAX {
        // Direct send: no slicing needed
        out.packets[0] = build_ip_packet(frame, 0, 1, 0, payload);
        out.count = 1;
        return 0;  // SYS_OK (P2-2)
    }
    // Slice into N IP packets (最多 MAX_SHIM_SLICES, 超出返 -ENOSPC)
    let total = (payload.len() + SHIM_PAYLOAD_MAX - 1) / SHIM_PAYLOAD_MAX;
    if total > MAX_SHIM_SLICES as usize {
        return -28;  // SYS_ENOSPC (P2-2: 错误码恒负)
    }
    for (i, chunk) in payload.chunks(SHIM_PAYLOAD_MAX).enumerate() {
        out.packets[i] = build_ip_packet(frame, i as u16, total as u16, (i * SHIM_PAYLOAD_MAX) as u16, chunk);
    }
    out.count = total as u8;
    0  // SYS_OK
}

/// Rx: reassemble IP packets → 1536B frame
/// P2-3: 返 i32 (P2-2 恒负错误码), 不返 Result (D90 红线); sys_error_t 是本文件内部私有类型, 不跨文档引用
pub fn shim_rx_reassemble(packets: &[IpPacket], out: &mut NetworkFrame) -> i32 {
    if packets.is_empty() { return -22; }  // SYS_EINVAL (P2-2)
    let first = &packets[0];
    let shim = unsafe { &*(first.payload.as_ptr() as *const shim_header_t) };
    if shim.shim_magic != 0xCAFE { return -22; }  // SYS_EINVAL
    // ... reassemble by shim_seq order into `out`
    // (返 0 SYS_OK 或负 SYS_ENOSPC/SYS_EIO 等)
    0
}
```

**Auto-detection** at boot:
1. NIC sends 1 probe packet with `MTU = 1536` + DF (don't fragment) bit
2. If ICMP Echo Reply received within 1 s → Jumbo Frame supported → `-Denable_shim=false`
3. Otherwise → Shim Layer stays ON

## D25: dev://uart0 (companion device)

dev://uart0 is the companion device file. It is **separate** from dev://network and uses the same Scheme Router pattern (D9.2). The UART driver uses a simple 16-byte ring buffer, no DMA, no Shim Layer (D25).

## Cross-references

- **Memory Subsystem** (09): MacDmaPool adjacent to BlockPool
- **ABI Contract** (04): NetworkFrame shares RpcUnit layout (D57)
- **Error Handling** (10): Shim Layer returns `SYS_EINVAL` on bad shim header
- **Documentation Gate** §二十.7: see gate catalog for forbidden phrases (R28 D96)

## Verification

- `make test-jumbo-on` — Shim Layer ON, 1500B MTU switch compatibility
- `make test-jumbo-off` — Shim Layer OFF, 1536B direct path
- `make test-mac-dma` — 256 mac_alloc + mac_free cycles, no leak
- `make test-shim-roundtrip` — 1536B frame → slice → reassemble, byte-identical
