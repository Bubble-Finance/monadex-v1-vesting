// Layout:
//     - pragma
//     - imports
//     - interfaces, libraries, contracts
//     - type declarations
//     - state variables
//     - events
//     - errors
//     - modifiers
//     - functions
//         - constructor
//         - receive function (if exists)
//         - fallback function (if exists)
//         - external
//         - public
//         - internal
//         - private
//         - view and pure functions

// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712} from "../lib/openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "../lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title MONADEX-VESTING.
 * @author Monadex Labs -- Ola Hamid.
 * @notice The MDX vesting contract is designed to Pay out monadex investors on a vested daily/      * weekly or monthly basis depending on the configurtions 
 */
contract MDXVesting is EIP712, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    //------------------//
    //-----ERROR--------//
    //------------------//
    error MDXVestingZeroAddressError();
    error MDXVestingZeroValueError();
    error MDXVestingConfigError();
    error MDXVestingCampaignIsCanceledError();
    error MDXVestingCampaignWrongActor();
    error MDXVestingCampaignIsNotRetrievable();
    error Monadex_invalidSignatureError();

    
    //------------------//
    //-----Event--------//
    //------------------//
    event E_vestingCreated(
        address indexed investorAddr,
        uint256 indexed amount,
        uint256 indexed duration
    );

    event E_MDXAdded(
        uint256 indexed 
    );

    event E_vestCanceled(
        address indexed investorAddr
    );

    event E_vestingReceived(
        address indexed investorAddr,
        uint256 indexed vestAmount,
        uint256 indexed remainingAmount
    );

    //--------------------------//
    //-----STATE VARIABLE-------//
    //-------------------------//

    struct investorsDetail {
        bytes32 investorID;
        uint256 investorIDX;
    }
    /// @notice A struct describing vesting destails for each investor
    struct vestingDetail {
        address investor;
        /// @dev interval day to start the vesting process, should not be zero
        uint256 startCliff;
        /// @dev current timstamp in which the vesting process is being started
        uint256 startDate;
        /// @dev amount in seconds that the vesting process will last for
        uint256 duration;
        /// @dev amount of slashes that the vesting process will be
        uint256 frequency;
        /// @dev boolean check if the vesting process is retrieveable or not
        bool retrievable;
        /// @dev total amount to be vested proportional to the ID attached to it
        uint256 amountTotal;
        /// @dev amount that is already retriened 
        uint256 retrieved;
        /// @dev ID vesting canceled or not
        bool cancel;
    }
    /// @dev protocol multi sig Address 
    address private immutable protocolMultiSigAddress;
    /// @dev MXD token to be vested
    IERC20 private immutable MDXtoken;
    /// @dev array of vesting IDs details
    bytes32[] private vestingDetailsIDs;
    /// @dev A private mapping of ID(key) => vestingDetails(vaule)
    mapping(bytes32 => vestingDetail) private s_VestingDetails;
    /// @dev total Vested Amount.
    uint256 private vestingTotalAmount;
    /// @dev a private mapping of investor address(key) => investorsDetail(value) 
    mapping(address => investorsDetail) private s_InvestorsDetails;

    /// @dev EIP-712 standard messageTypeHash definitions
    bytes32 private constant messageTypeHash = keccak256("vestingDetail(address investor, uint256 startCliff, uint256 startDate, uint256 duration, uint256 frequency, bool retrievable, uint256 amountTotal, uint256 retrieved, bool cancel");

    //-----------------------//
    //-------modifier--------//
    //-----------------------//
    modifier ifVestingCampaignIsCancelled(bytes32 _vestingDetailID) {
            vestingDetail memory _vestingDetail = s_VestingDetails[_vestingDetailID];
            if (_vestingDetail.cancel == true){
                revert MDXVestingCampaignIsCanceledError();
            }
        _;
    }

    //-----------------------//
    //-----CONSTRUCTOR-------//
    //-----------------------//
    constructor(address _MonadexMultiSigAddress, ERC20 _token) Ownable(_MonadexMultiSigAddress) EIP712("MDXVesting", "1") {
        if (_MonadexMultiSigAddress == address(0)) {
            revert MDXVestingZeroAddressError();
        }
        protocolMultiSigAddress =_MonadexMultiSigAddress;
        MDXtoken = _token;
    }

    //-----------------------//
    //-------FUNCTIONS-------//
    //-----------------------//

    /**
     * @notice the createVesting Function allow the protocol team to crate a vesting for a particular investor, depending on the custom arrangment
     * @param _vestingDetail passes in the the custom vesting detials of the investor
     */
    function createVesting(
        vestingDetail calldata _vestingDetail
    )
         public
        onlyOwner
    {
        if (_vestingDetail.investor == address(0)) {
            revert MDXVestingZeroAddressError();
        }
        if (
            _vestingDetail.startCliff == 0 ||
             _vestingDetail.startDate == 0 ||
              _vestingDetail.frequency == 0||
               _vestingDetail.duration == 0
        ) {
            revert MDXVestingZeroValueError();
        }
        // Set a require statement to check the duration is higher than the cliff
        if (
            _vestingDetail.startDate > _vestingDetail.startCliff ||
            _vestingDetail.startCliff > _vestingDetail.duration
        ) {
            revert MDXVestingConfigError();
        }

        uint256 _cliff = _vestingDetail.startDate + _vestingDetail.startCliff;
        uint256 _duration = _vestingDetail.startDate + _vestingDetail.startCliff + _vestingDetail.duration;
        bytes32 vestingID = calculateNextVestingDetailIDforAddrAndIdx(_vestingDetail.investor);
        vestingDetail memory _newVestingDetail = vestingDetail(
            _vestingDetail.investor,
            _cliff,
            _vestingDetail.startDate,
            _duration,
            _vestingDetail.frequency,
            _vestingDetail.retrievable,
            _vestingDetail.amountTotal,
            0,
            false
        );
        s_VestingDetails[vestingID] = _newVestingDetail;
        vestingTotalAmount = vestingTotalAmount + _vestingDetail.amountTotal;
        vestingDetailsIDs.push(vestingID);

        investorsDetail memory _investorDetail = s_InvestorsDetails[_vestingDetail.investor];

        uint256 investorIdx = _investorDetail.investorIDX;
        _investorDetail.investorIDX = investorIdx + 1;

        emit E_vestingCreated(_newVestingDetail.investor, _newVestingDetail.duration, _newVestingDetail.amountTotal);

    }
    /**
     * @notice The function allow the Monadex Protocol Team to create a vesting and pay 
     * @param _vestingDetail passes in the the custom vesting detials of the investor
     * @param _amount amount to be added to the contract by the team
     */
    function createAndAddToken(
        vestingDetail calldata _vestingDetail, 
        uint256 _amount
    ) 
        external 
        onlyOwner 
    {
        createVesting(_vestingDetail);
        addMDXToken(_amount);
    }
    /**
     * @notice This function can only be called by the retriving investor and the monadex Team
     * @param _vestingDetailID byte32 investor
     * @param _amount amount to be vested out
     */
    function retrieve(
        bytes32 _vestingDetailID,
        uint256 _amount, 
        uint8 v,
        bytes32 r, 
        bytes32 s
    ) 
        public 
        nonReentrant 
        ifVestingCampaignIsCancelled(_vestingDetailID) 
    {
        if (_amount == 0) {
            revert MDXVestingZeroValueError();
        }
        vestingDetail memory _vestingDetail = s_VestingDetails[_vestingDetailID];

        address investorAddr = _vestingDetail.investor;
        if (investorAddr == address(0)) {
            revert MDXVestingZeroAddressError();
        }
        if (msg.sender != investorAddr || msg.sender != protocolMultiSigAddress) {
            revert MDXVestingCampaignWrongActor();
        }

        uint256 vestedAmount = calculateAmountToRetrieve(_vestingDetail);
        if (_amount > vestedAmount) {
            revert MDXVestingConfigError();
        }
        if (isValidSignature(investorAddr, getDigest(investorAddr, _vestingDetail.startCliff, _vestingDetail.startDate, _vestingDetail.duration, _vestingDetail.frequency, _vestingDetail.retrievable, _vestingDetail.amountTotal, _vestingDetail.retrieved, _vestingDetail.cancel), v, r, s) != true) {
            revert Monadex_invalidSignatureError();
        }
        _vestingDetail.retrieved = _vestingDetail.retrieved + _amount;
        _vestingDetail.amountTotal = _vestingDetail.amountTotal - _amount;
        vestingTotalAmount = vestingTotalAmount - _amount;

        MDXtoken.safeTransferFrom(address(this),investorAddr, _amount);
        emit E_vestingReceived(investorAddr, _amount,_vestingDetail.amountTotal );
    } 
    /**
     * @notice the cancelVest function allow you to cancel a particular vesting Operation and pay out the right amount of token in respect to the current date to the investor and the rest stays in the contract
     * @param _investorID the ID bytes32 of the investor
     */
    function cancelVest(
        bytes32 _investorID,
        uint8 v,
        bytes32 r,
        bytes32 s
        ) 
    external
    ifVestingCampaignIsCancelled(_investorID) onlyOwner {
        vestingDetail memory _vestingDetail = s_VestingDetails[_investorID];

        if (_vestingDetail.retrievable != true) {
            revert MDXVestingCampaignIsNotRetrievable();
        }
        uint256 vestedAmount = calculateAmountToRetrieve(_vestingDetail);
        if (vestedAmount > 0) {
            retrieve(_investorID, vestedAmount, v, r, s);
        }

        uint256 unRetrieved = _vestingDetail.amountTotal - _vestingDetail.retrieved;
        _vestingDetail.amountTotal = _vestingDetail.amountTotal - unRetrieved;

        _vestingDetail.cancel == true;

        emit E_vestCanceled(_vestingDetail.investor);
    }
    /**
     * @notice the function allows you to add MDX to the contract
     * @param _amount amount to be added to the contract
     */
    function addMDXToken(uint _amount) public onlyOwner {
        if (_amount == 0) {
            revert MDXVestingZeroValueError();
        }
        MDXtoken.safeTransferFrom(msg.sender, address(this), _amount);
    }
    /**
     * @notice this fucntion allow the protocols Team to withdraw from the contract back to the protocolTeam Address 
     * @param _amount amount to be witdraw from the contract
     */
    function withDrawMDXToken(uint _amount) external onlyOwner {
        if (_amount == 0) {
            revert MDXVestingZeroValueError();
        }
        MDXtoken.safeTransferFrom(address(this), msg.sender, _amount);

        emit E_MDXAdded(_amount);
    }

    //----------------------------------//
    //-----internal&get Functions-------//
    //----------------------------------//

    /**
     * @notice this function hashes the address and the index of the investor
     * @param investor address 
     * @param idx investor Inex in uint
     */
    function calculateVestingSchedureIDforAddrAndIdx(address investor, uint idx) public pure returns(bytes32) {
        return keccak256(abi.encodePacked(investor, idx));
    }
    /**
     * @notice this function hashes out the adress and index of the investor and return an ID of
     * bytes32
     * @param investor ADDRESS of investor 
     */
    function calculateNextVestingDetailIDforAddrAndIdx(address investor) public view returns (bytes32) {
        investorsDetail memory _investorsDetail = s_InvestorsDetails[investor];
        return calculateVestingSchedureIDforAddrAndIdx (investor, _investorsDetail.investorIDX);
    }
    /**
     * @return current Time stamp
     */
    function getCurrentTime() public view returns(uint256) {
        return block.timestamp;
    }
    /**
     * @notice This Function calculates the amount to retrieved
     * @param _vestingDetail the investor detail
     * @return returns the amount to be retrived depending on the vesting details
     */
    function calculateAmountToRetrieve(vestingDetail memory _vestingDetail) internal view returns(uint256) {
        uint currentTime = getCurrentTime();
        // if the curentTime is less than the time after the cliff, or if the it is terminated
        if (currentTime < ((_vestingDetail.startDate + _vestingDetail.startCliff)) || (_vestingDetail.cancel == true)) {
            return 0;
        }
        // if current time is greater than the uration given it returns the total amount of vested MDX left
        else if (currentTime > (_vestingDetail.startDate + _vestingDetail.startCliff + _vestingDetail.duration)) {
            return (_vestingDetail.amountTotal - _vestingDetail.retrieved);
        }
        else {
            uint256 unitPerVestingAmount = _vestingDetail.amountTotal/_vestingDetail.frequency; // 1000/10 ~1000eth/4
            uint256 unitPerDuration = _vestingDetail.duration/_vestingDetail.frequency; //100days/4
            uint256 durationToCurrentTime = currentTime - (_vestingDetail.startDate + _vestingDetail.startCliff); //50days
            uint256 updateUnitPerDurtion = durationToCurrentTime / unitPerDuration;
            uint256 durationVestingAmount = updateUnitPerDurtion * unitPerVestingAmount;

            return (durationVestingAmount - _vestingDetail.retrieved);

        }
    }
    /**
     * @notice gets the investor details
     * @param _investorAddr get investor detail through investor address 
     */
    function getInvestorDetailByAddress(address _investorAddr) external view returns (investorsDetail memory ) {
        return s_InvestorsDetails[_investorAddr];
    }
    /**
     * @notice the fucntion get the vesting information by bytes32 ID 
     * @param _vestingDetailID pass in the investor VestingDetailID
     */
    function getVestingDetailByBytes(bytes32 _vestingDetailID) external view returns (vestingDetail memory) {
        return s_VestingDetails[_vestingDetailID];
    }
    /**
     * @notice the fucntion get the vesting information for an investor by address 
     * @param _investorAddr pass in the address of the investor
     */
    function getVestingDetailByAddress (address _investorAddr) external view returns (vestingDetail memory) {
        investorsDetail memory _investorDetail = s_InvestorsDetails[_investorAddr];
        bytes32 _investorID = _investorDetail.investorID;
        return s_VestingDetails[_investorID];
    }
    /**
     * @return protocolTeamAddress
     */
    function getProtocolTeamAddr() external view returns (address ) {
        return protocolMultiSigAddress;
    }
    /**
     * @return the count Amount of vesting investors 
     */
    function getVestedInvestorsCount() external view returns (uint) {
        return vestingDetailsIDs.length;
    }

    function getTotalAmountForVesting() external view returns (uint) {
        return vestingTotalAmount;
    }

    function isValidSignature(
        address retreiver,
        bytes32 digest, 
        uint8 v,
        bytes32 r,
        bytes32 s 
        ) internal pure returns(bool) {
            (address actualSigner, , ) = ECDSA.tryRecover(digest, v, r, s);

            return (actualSigner == retreiver);
        }

    function getDigest(
        address _investor,
        uint256 _startCliff,
        uint256 _startDate,
        uint256 _duration,
        uint256 _frequency,
        bool _retrievable,
        uint256 _amountTotal,
        uint256 _retrieved,
        bool _cancel) public view returns (bytes32) {
        // MDXVestingTypes.vestingDetail memory _vestingDetail = s_VestingDetails[_vestingDetailID];
        bytes32 hashedData = _hashTypedDataV4(keccak256(abi.encode(messageTypeHash, vestingDetail({
            investor : _investor,
            startCliff : _startCliff,
            startDate : _startDate,
            duration : _duration,
            frequency : _frequency,
            retrievable : _retrievable,
            amountTotal : _amountTotal,
            retrieved : _retrieved,
            cancel : _cancel
        })
      )));
      return hashedData;
    }
    function getCurrentContractBalance() external onlyOwner view returns (uint) {
        return MDXtoken.balanceOf(address(this));
    }
    function getCurrentAmountBeingVested() external onlyOwner view returns (uint) {
        return vestingTotalAmount;
    }

    function getUnVestedAmount() external onlyOwner view returns (uint) {
        uint unvested = MDXtoken.balanceOf(address(this)) - vestingTotalAmount;
        return unvested;
    }
    
}
