// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

/**
 * @title IComplianceModule
 * @dev Interface for pluggable compliance modules
 * @notice All compliance modules must implement this interface to be compatible with ModularCompliance
 */
interface IComplianceModule {
    /**
     * @notice Check if a transfer is compliant
     * @param _from Sender address
     * @param _to Recipient address
     * @param _amount Transfer amount
     * @return True if transfer is allowed
     */
    function canTransfer(address _from, address _to, uint256 _amount) external view returns (bool);

    /**
     * @dev Called after a successful transfer
     * @param _from Sender address
     * @param _to Recipient address
     * @param _amount Transfer amount
     */
    function transferred(address _from, address _to, uint256 _amount) external;

    /**
     * @dev Called when tokens are created (minted)
     * @param _to Receiver address
     * @param _amount Amount minted
     */
    function created(address _to, uint256 _amount) external;

    /**
     * @dev Called when tokens are destroyed (burned)
     * @param _from Sender address
     * @param _amount Amount burned
     */
    function destroyed(address _from, uint256 _amount) external;

    /**
     * @dev Check if module is compatible with a compliance contract
     * @param _compliance Address of the compliance contract
     * @return True if module is bound to this compliance
     */
    function moduleCheck(address _compliance) external view returns (bool);
}
