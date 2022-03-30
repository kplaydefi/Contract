pragma solidity >=0.5.0 <0.7.0;

import "../../erc20/ERC20Storage.sol";

interface IKPTMortgage {
    function transfer(address to, uint value) external returns (bool);
    function innerTransfer(address account, address receiver, uint256 amount) external returns (bool);
    function innerTransferFrom(address from, address to, uint256 amount) external returns (bool);
    function getTotalMortgage() external view returns (uint);
    function redemption(address account, uint256 amount) external returns (bool);
    function mortgage(address account, uint256 amount) external returns (bool);
    function database() external returns (ERC20Storage);
    function balanceOf(address account) external view returns (uint256);
    function transferReward(uint256 amount) external;

}