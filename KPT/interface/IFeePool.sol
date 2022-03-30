pragma solidity >=0.5.0 <0.7.0;


contract IFeePool {
    function setReward(uint256 remainder) external;

    function exchangeFeeRate() external view returns (uint);

    function recordFeePaid(uint amount) external;

    function FEE_ADDRESS() external view returns (address);

    function appendAccountIssuanceRecord(address account, uint debtRatio, uint debtEntryIndex) external;
}
