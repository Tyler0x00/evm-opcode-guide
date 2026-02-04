// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title BytecodeDeployer
/// @author Tyler0x00
/// @custom:disclaimer Unaudited code. Review before use in production.
/// @notice Deploys your bytecode EXACTLY as provided - no init code interference
/// @dev Normal CREATE executes deployed code and uses RETURN value as final bytecode.
///      This bypasses that by wrapping your code in minimal init code that simply
///      copies and returns your bytecode unchanged.
contract BytecodeDeployer {
    error DeployFailed();

    /// @notice Deploy bytecode exactly as-is. What you pass is what gets deployed.
    /// @param bytecode Raw runtime bytecode to deploy (NOT init code)
    /// @return deployed Address where your exact bytecode now lives
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
}
