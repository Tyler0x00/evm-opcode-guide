# Deploy Your Exact Bytecode As-Is

## Quick Copy-Paste

**Solidity** - embed in your contract
```solidity
function deployExact(bytes calldata bytecode) external payable returns (address deployed) {
    // Wrap in minimal init code: CODECOPY + RETURN (12 bytes)
    // Result: deployed contract code == bytecode (byte-for-byte identical)
    bytes memory initCode = abi.encodePacked(
        hex"61", bytes2(uint16(bytecode.length)),
        hex"600c5f3961", bytes2(uint16(bytecode.length)),
        hex"5ff3", bytecode
    );
    assembly ("memory-safe") {
        deployed := create(callvalue(), add(initCode, 0x20), mload(initCode))
    }
    if (deployed == address(0)) revert DeployFailed();
}
```

**Solidity** - standalone contract: [BytecodeDeployer.sol](./BytecodeDeployer.sol)

**Go** - generate init code
```go
func ToInitcode(bytecode string) string {
    bytecode = strings.TrimPrefix(bytecode, "0x")
    length := len(bytecode) / 2
    return fmt.Sprintf("61%04x600c5f3961%04x5ff3%s", length, length, bytecode)
}
```

---

## The Problem

When you write gas-optimized contracts directly in opcodes (like MEV bots such as jaredfromsubway's), you typically don't create initialization code. You just have the raw runtime bytecode you want deployed exactly as-is.

This is also extremely useful when you want to redeploy an already deployed contract's bytecode - perhaps for testing on Etherscan, or to deploy a slightly modified version (e.g., swapping out the AUTH address to your own).

But here's the catch: **you can't just deploy raw bytecode directly**.

The only way to deploy code is through `CREATE` or `CREATE2` opcodes, and they have a specific behavior that we must work with.

## How CREATE/CREATE2 Actually Works

1. When `CREATE`/`CREATE2` is called, it deploys `[code + constructor args (if any)]` to the designated address
2. It then **executes** the deployed code
3. Whatever this code `RETURN`s becomes the **final deployed bytecode**

This is EVM spec - you can't change it. So we need to hack this mechanism to deploy our raw bytecode.

## The Solution: Minimal Init Code

We need init code that:
1. Copies our actual bytecode from the init code itself
2. Returns it as the final contract code

Here's the most compact and clear approach:

### Init Code Structure

```
PUSH2 len([byteCode])    // Length for CODECOPY (2 bytes covers max 24KB - EIP-170 limit)
PUSH1 0x0c               // Offset where bytecode starts (= init code length)
PUSH0                    // Memory destination (0x00)
CODECOPY                 // Copy bytecode to memory
PUSH2 len([byteCode])    // Length for RETURN
PUSH0                    // Memory offset (0x00)
RETURN                   // Return the bytecode
[byteCode]               // Your actual bytecode appended here
```

### Opcode Breakdown

| Opcode | Hex | Description |
|--------|-----|-------------|
| `PUSH2` | `0x61` | Push 2-byte length (padded!) |
| `PUSH1` | `0x60` | Push 1-byte offset |
| `PUSH0` | `0x5f` | Push zero |
| `CODECOPY` | `0x39` | Copy code to memory |
| `RETURN` | `0xf3` | Return memory slice |

### Concrete Example

Let's deploy `0x6212345660005260206000f3` (a simple contract that always returns `0x123456`).

```
byteCode = 0x6212345660005260206000f3
len([byteCode]) = 12 bytes = 0x0c
```

**Building the init code:**

```
61 000c    // PUSH2 0x000c (length = 12, MUST be 2 bytes!)
60 0c      // PUSH1 0x0c (offset = 12, where bytecode starts)
5f         // PUSH0 (memory dest = 0)
39         // CODECOPY
61 000c    // PUSH2 0x000c (length for RETURN)
5f         // PUSH0 (memory offset = 0)
f3         // RETURN
6212345660005260206000f3  // The actual bytecode
```

**Final init code:**
```
61000c600c5f3961000c5ff36212345660005260206000f3
```

Deploy this, and your contract will have exactly `0x6212345660005260206000f3` as its bytecode.

## Key Points

- **Length must be 2 bytes**: Always pad with zeros (e.g., `000c` not `0c`)
- **Init code is always 12 bytes**: The offset `0x0c` is constant
- **Max bytecode size is 24KB**: `PUSH2` covers `0x0000` to `0xFFFF` (65,535 bytes), more than enough
- **Don't count hex string characters**: `0x6212345660005260206000f3` is 12 bytes, not 24
