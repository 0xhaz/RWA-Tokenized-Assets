// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC3643} from "../interfaces/IERC3643.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {ICompliance} from "../interfaces/ICompliance.sol";

/**
 * @title TREXToken
 * @dev ERC-3643 compliant permissioned token with identity verification and compliance
 */
contract TREXToken is IERC3643, ERC20, Ownable, Pausable {
    /// @dev Identity Registry for KYC/AML checks
    IIdentityRegistry public identityRegistry;

    /// @dev Compliance contract
    ICompliance public compliance;

    /// @dev OnchainID address for token metadata
    address public onchainId;

    /// @dev Token version
    string private constant VERSION = "1.0.0";

    /// @dev Mapping of frozen addresses
    mapping(address => bool) private _frozen;

    /// @dev Mapping of frozen token amounts
    mapping(address => uint256) private _frozenTokens;

    // @dev Mapping of agent addresses
    mapping(address => bool) private _agents;

    /// @dev Custom errors
    error InvalidAddress();
    error OnlyAgent();
    error WalletFrozen();
    error InsufficientBalance();
    error TransferNotPossible();
    error NotVerified();
    error ComplianceCheckFailed();

    /// @dev Modifiers
    modifier onlyAgent() {
        if (!_agents[msg.sender]) revert OnlyAgent();
        _;
    }

    /**
     * @dev Constructor
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param decimals_ Token decimals
     * @param identityRegistry_ Identity Registry address
     * @param compliance_ Compliance contract address
     * @param onchainId_ OnchainID address
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address identityRegistry_,
        address compliance_,
        address onchainId_
    ) ERC20(name_, symbol_) Ownable(msg.sender) {
        if (identityRegistry_ == address(0)) revert InvalidAddress();
        if (compliance_ == address(0)) revert InvalidAddress();

        identityRegistry = IIdentityRegistry(identityRegistry_);
        compliance = ICompliance(compliance_);
        onchainId = onchainId_;

        // OpenZeppelin ERC20 doesn't allow custom decimals in constructor
        // We'll use the default 18 decimals
    }

    /*//////////////////////////////////////////////////////////////
                           OVERRIDE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function name() public view override(ERC20, IERC3643) returns (string memory) {
        return ERC20.name();
    }

    function symbol() public view override(ERC20, IERC3643) returns (string memory) {
        return ERC20.symbol();
    }

    function decimals() public view override(ERC20, IERC3643) returns (uint8) {
        return ERC20.decimals();
    }

    function paused() public view override(Pausable, IERC3643) returns (bool) {
        return Pausable.paused();
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function version() external pure returns (string memory) {
        return VERSION;
    }

    function isFrozen(address _userAddress) external view returns (bool) {
        return _frozen[_userAddress];
    }

    function getFrozenTokens(address _userAddress) external view returns (uint256) {
        return _frozenTokens[_userAddress];
    }

    function isAgent(address _address) external view returns (bool) {
        return _agents[_address];
    }

    /*//////////////////////////////////////////////////////////////
                        CONFIGURATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setName(string calldata _name) external pure {
        // Name is immutable in this implementation
        revert("Name immutable");
    }

    function setSymbol(string calldata _symbol) external pure {
        // Symbol is immutable in this implementation
        revert("Symbol immutable");
    }

    function setOnchainID(address _onchainId) external onlyOwner {
        onchainId = _onchainId;
        emit UpdatedTokenInformation(name(), symbol(), decimals(), VERSION, _onchainId);
    }

    function setIdentityRegistry(address _identityRegistry) external onlyOwner {
        if (_identityRegistry == address(0)) revert InvalidAddress();
        identityRegistry = IIdentityRegistry(_identityRegistry);

        emit IdentityRegistryAdded(_identityRegistry);
    }

    function setCompliance(address _compliance) external onlyOwner {
        if (_compliance == address(0)) revert InvalidAddress();

        compliance = ICompliance(_compliance);
        emit ComplianceAdded(_compliance);
    }

    /*//////////////////////////////////////////////////////////////
                            PAUSE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                            AGENT MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function addAgent(address _agent) external onlyOwner {
        _agents[_agent] = true;
        emit AgentAdded(_agent);
    }

    function removeAgent(address _agent) external onlyOwner {
        _agents[_agent] = false;
        emit AgentRemoved(_agent);
    }

    /*//////////////////////////////////////////////////////////////
                            FREEZE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setAddressFrozen(address _userAddress, bool _freeze) external onlyAgent {
        _frozen[_userAddress] = _freeze;
        emit AddressFrozen(_userAddress, _freeze, msg.sender);
    }

    function freezePartialTokens(address _userAddress, uint256 _amount) external onlyAgent {
        _frozenTokens[_userAddress] += _amount;
        emit TokensFrozen(_userAddress, _amount);
    }

    function unfreezePartialTokens(address _userAddress, uint256 _amount) external onlyAgent {
        if (_frozenTokens[_userAddress] >= _amount) {
            _frozenTokens[_userAddress] -= _amount;
        } else {
            _frozenTokens[_userAddress] = 0;
        }
        emit TokensUnfrozen(_userAddress, _amount);
    }

    function batchSetAddressFrozen(address[] calldata _userAddresses, bool[] calldata _freeze) external onlyAgent {
        require(_userAddresses.length == _freeze.length, "Length mismatch");
        for (uint256 i = 0; i < _userAddresses.length; i++) {
            _frozen[_userAddresses[i]] = _freeze[i];
            emit AddressFrozen(_userAddresses[i], _freeze[i], msg.sender);
        }
    }

    function batchFreezePartialTokens(address[] calldata _userAddresses, uint256[] calldata _amounts)
        external
        onlyAgent
    {
        require(_userAddresses.length == _amounts.length, "Length mismatch");
        for (uint256 i = 0; i < _userAddresses.length; i++) {
            _frozenTokens[_userAddresses[i]] += _amounts[i];
            emit TokensFrozen(_userAddresses[i], _amounts[i]);
        }
    }

    function batchUnfreezePartialTokens(address[] calldata _userAddresses, uint256[] calldata _amounts)
        external
        onlyAgent
    {
        require(_userAddresses.length == _amounts.length, "Length mismatch");
        for (uint256 i = 0; i < _userAddresses.length; i++) {
            if (_frozenTokens[_userAddresses[i]] >= _amounts[i]) {
                _frozenTokens[_userAddresses[i]] -= _amounts[i];
            } else {
                _frozenTokens[_userAddresses[i]] = 0;
            }
            emit TokensUnfrozen(_userAddresses[i], _amounts[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                          MINT/BURN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function mint(address _to, uint256 _amount) external onlyOwner whenNotPaused {
        _mint(_to, _amount);
        compliance.created(_to, _amount);
    }

    function burn(address _userAddress, uint256 _amount) external onlyAgent whenNotPaused {
        _burn(_userAddress, _amount);
        compliance.destroyed(_userAddress, _amount);
    }

    function batchMint(address[] calldata _toList, uint256[] calldata _amounts) external onlyOwner whenNotPaused {
        require(_toList.length == _amounts.length, "Length mismatch");
        for (uint256 i = 0; i < _toList.length; i++) {
            _mint(_toList[i], _amounts[i]);
            compliance.created(_toList[i], _amounts[i]);
        }
    }

    function batchBurn(address[] calldata _userAddresses, uint256[] calldata _amounts)
        external
        onlyAgent
        whenNotPaused
    {
        require(_userAddresses.length == _amounts.length, "Length mismatch");
        for (uint256 i = 0; i < _userAddresses.length; i++) {
            _burn(_userAddresses[i], _amounts[i]);
            compliance.destroyed(_userAddresses[i], _amounts[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                           TRANSFER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function transfer(address _to, uint256 _amount) public override(ERC20, IERC20) whenNotPaused returns (bool) {
        if (_frozen[msg.sender]) revert WalletFrozen();
        if (_frozen[_to]) revert WalletFrozen();

        uint256 freeBalance = balanceOf(msg.sender) - _frozenTokens[msg.sender];
        if (_amount > freeBalance) revert InsufficientBalance();

        if (!identityRegistry.isVerified(_to)) revert NotVerified();
        if (!compliance.canTransfer(msg.sender, _to, _amount)) revert ComplianceCheckFailed();

        _transfer(msg.sender, _to, _amount);
        compliance.transferred(msg.sender, _to, _amount);

        return true;
    }

    function transferFrom(address _from, address _to, uint256 _amount)
        public
        override(ERC20, IERC20)
        whenNotPaused
        returns (bool)
    {
        if (_frozen[_from]) revert WalletFrozen();
        if (_frozen[_to]) revert WalletFrozen();

        uint256 freeBalance = balanceOf(_from) - _frozenTokens[_from];
        if (_amount > freeBalance) revert InsufficientBalance();

        if (!identityRegistry.isVerified(_to)) revert NotVerified();
        if (!compliance.canTransfer(_from, _to, _amount)) revert ComplianceCheckFailed();

        _spendAllowance(_from, msg.sender, _amount);
        _transfer(_from, _to, _amount);
        compliance.transferred(_from, _to, _amount);

        return true;
    }

    function forcedTransfer(address _from, address _to, uint256 _amount)
        external
        onlyAgent
        whenNotPaused
        returns (bool)
    {
        uint256 freeBalance = balanceOf(_from) - _frozenTokens[_from];
        if (_amount > freeBalance) revert InsufficientBalance();

        _transfer(_from, _to, _amount);
        compliance.transferred(_from, _to, _amount);

        return true;
    }

    function batchTransfer(address[] calldata _toList, uint256[] calldata _amounts) external whenNotPaused {
        require(_toList.length == _amounts.length, "Length mismatch");
        for (uint256 i = 0; i < _toList.length; i++) {
            transfer(_toList[i], _amounts[i]);
        }
    }

    function batchForcedTransfer(address[] calldata _fromList, address[] calldata _toList, uint256[] calldata _amounts)
        external
        onlyAgent
        whenNotPaused
    {
        require(_fromList.length == _toList.length, "Length mismatch");
        require(_fromList.length == _amounts.length, "Length mismatch");

        for (uint256 i = 0; i < _fromList.length; i++) {
            uint256 freeBalance = balanceOf(_fromList[i]) - _frozenTokens[_fromList[i]];
            if (_amounts[i] > freeBalance) revert InsufficientBalance();

            _transfer(_fromList[i], _toList[i], _amounts[i]);
            compliance.transferred(_fromList[i], _toList[i], _amounts[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                           RECOVERY FUNCTION
    //////////////////////////////////////////////////////////////*/
    function recoveryAddress(address _lostWallet, address _newWallet, address _investorOnchainID)
        external
        onlyAgent
        returns (bool)
    {
        if (_frozen[_lostWallet]) revert WalletFrozen();

        uint256 balance = balanceOf(_lostWallet);
        uint256 frozenTokens = _frozenTokens[_lostWallet];

        if (balance > 0) {
            _transfer(_lostWallet, _newWallet, balance);
        }

        if (frozenTokens > 0) {
            _frozenTokens[_newWallet] += frozenTokens;
            _frozenTokens[_lostWallet] = 0;
        }

        emit RecoverySuccess(_lostWallet, _newWallet, _investorOnchainID);

        return true;
    }
}
