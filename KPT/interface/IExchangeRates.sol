pragma solidity >=0.5.0 <0.7.0;


interface IExchangeRates {
    function ratio(bytes32 source, uint256 amount, bytes32 destination) external view returns (uint256);

    function getFeedPrice(bytes32 currency) external view returns (uint256);

    function getFeedPrices(bytes32[] calldata currencies) external view returns (uint256[] memory);

    function isExpired(bytes32 currency) external view returns (bool);

    function isAnyExpired(bytes32[] calldata currencies) external view returns (bool);

    function getFeedPricesAndAnyExpired(bytes32[] calldata currencies) external view returns (uint256[] memory, bool);
}
