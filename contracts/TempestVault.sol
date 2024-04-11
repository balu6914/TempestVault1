// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@ambient-protocol/ambient.js/dist/index.js";

contract TempestProVault is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public factory;
    address public token0;
    address public token1;
    int24 public tickSpacing;
    address public poolAddress;
    INonfungiblePositionManager public nonfungiblePositionManager;
    IWETH public WETH;

    constructor(
        address _factory,
        address _token0,
        address _token1,
        int24 _tickSpacing,
        address _poolAddress
    ) {
        factory = _factory;
        token0 = _token0;
        token1 = _token1;
        tickSpacing = _tickSpacing;
        poolAddress = _poolAddress;
        nonfungiblePositionManager = INonfungiblePositionManager(_poolAddress);
        WETH = IWETH(address(0));
    }

    function _mintInitial() internal {
    // Get token balances
    uint256 balance0 = IERC20(token0).balanceOf(address(this));
    uint256 balance1 = IERC20(token1).balanceOf(address(this));
    
    // Approve spending of tokens by NonfungiblePositionManager
    IERC20(token0).approve(address(nonfungiblePositionManager), balance0);
    IERC20(token1).approve(address(nonfungiblePositionManager), balance1);
    
    // Specify position parameters
    INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
        token0: token0,
        token1: token1,
        fee: 3000, // Fee in basis points (30)
        tickLower: TickMath.MIN_TICK,
        tickUpper: TickMath.MAX_TICK,
        amount0Desired: balance0,
        amount1Desired: balance1,
        amount0Min: 0,
        amount1Min: 0,
        recipient: address(this),
        deadline: block.timestamp // Use current block timestamp as the deadline
     });
    
    // Mint initial liquidity
    nonfungiblePositionManager.mint(params);
    }

    function approveRouter() external {
    // Approve spending of token0 and token1 by the Ambient router
    IERC20(token0).approve(address(ambientRouter), type(uint256).max);
    IERC20(token1).approve(address(ambientRouter), type(uint256).max);
    }

    function poke(int24 tickLower, int24 tickUpper) external {
    // Update earned fees in the Ambient pool for the given price range
    nonfungiblePositionManager.collect(INonfungiblePositionManager.CollectParams({
        tokenId: 0, // Set to 0 to collect from all positions
        recipient: address(this), // Address to receive the fees
        tickLower: tickLower,
        tickUpper: tickUpper,
        amount0Max: type(uint128).max,
        amount1Max: type(uint128).max
      }));
    }

    function _poke(int24 tickLower, int24 tickUpper) internal {
    // Update earned fees in the Ambient pool for the given price range
    poke(tickLower, tickUpper);
     }

    function deposit(
    uint256 amount0Desired,
    uint256 amount1Desired,
    uint256 amount0Min,
    uint256 amount1Min,
    address to
     ) 
     external nonReentrant {
    // Transfer tokens from the sender to the contract
    require(
        IERC20(token0).transferFrom(msg.sender, address(this), amount0Desired),
        "Transfer of token0 failed"
    );
    require(
        IERC20(token1).transferFrom(msg.sender, address(this), amount1Desired),
        "Transfer of token1 failed"
    );

    // Approve spending of tokens by the contract
    IERC20(token0).approve(address(nonfungiblePositionManager), amount0Desired);
    IERC20(token1).approve(address(nonfungiblePositionManager), amount1Desired);

    // Provide liquidity to the Ambient pool
    nonfungiblePositionManager.mint(
        INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: 3000, // Fee calculated as 0.3%
            tickLower: tickSpacing * (int24(amount0Desired) / int24(amount1Desired)),
            tickUpper: tickSpacing * (int24(amount0Desired) / int24(amount1Desired) + 1),
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            recipient: to,
            deadline: block.timestamp // Use current block timestamp as deadline
        })
      );
    }


    function _poke(int24 tickLower, int24 tickUpper) internal {
    // Fetch the current liquidity position from the Ambient pool
    (, , uint128 liquidity, , , , ) = nonfungiblePositionManager.positions(
        keccak256(abi.encodePacked(address(this), tickLower, tickUpper))
    );

    // Withdraw liquidity from the specified price range
    nonfungiblePositionManager.decreaseLiquidity(
        INonfungiblePositionManager.DecreaseLiquidityParams({
            tokenId: tokenId,
            liquidity: liquidity,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp // Use current block timestamp as deadline
        })
    );

    // Deposit the same liquidity back into the specified price range
    nonfungiblePositionManager.increaseLiquidity(
        INonfungiblePositionManager.IncreaseLiquidityParams({
            tokenId: tokenId,
            amount0Desired: 0, // Maintain the same amount of token0
            amount1Desired: 0, // Maintain the same amount of token1
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp // Use current block timestamp as deadline
        })
      );
    }

    function _calcSharesAndAmounts(uint256 amount0Desired, uint256 amount1Desired) internal view returns (uint256, uint256) {
    // Fetch the current total holdings of token0 and token1 in the vault
    (uint256 totalAmount0, uint256 totalAmount1) = getTotalAmounts();

    // Calculate the proportion of desired amounts relative to total holdings
    uint256 share0 = (amount0Desired * totalSupply()) / totalAmount0;
    uint256 share1 = (amount1Desired * totalSupply()) / totalAmount1;

    // Return the largest possible amounts of token0 and token1 to deposit
    return (share0, share1);
    }


    function withdraw(uint256 shares, uint256 amount0Min, uint256 amount1Min, address to) external nonReentrant {
    require(shares > 0, "Shares must be greater than zero");

    // Fetch the current total holdings of token0 and token1 in the vault
    (uint256 totalAmount0, uint256 totalAmount1) = getTotalAmounts();

    // Calculate the amounts of token0 and token1 to withdraw based on the shares provided
    uint256 amount0 = (shares * totalAmount0) / totalSupply();
    uint256 amount1 = (shares * totalAmount1) / totalSupply();

    // Ensure that the calculated amounts are not less than the minimum specified
    require(amount0 >= amount0Min, "Amount0 too low");
    require(amount1 >= amount1Min, "Amount1 too low");

    // Transfer the calculated amounts of token0 and token1 to the recipient
    IERC20(token0).transfer(to, amount0);
    IERC20(token1).transfer(to, amount1);

    // Emit event
    emit Withdrawn(to, shares, amount0, amount1);
    }


    function _burnLiquidityShare(
    int24 tickLower,
    int24 tickUpper,
    uint256 shares,
    uint256 totalSupply
     ) 
    internal {
    require(shares > 0, "Shares must be greater than zero");

    // Calculate the liquidity share to burn
    uint128 liquidityToBurn = uint128((uint256(shares) * nonfungiblePositionManager.totalSupply()) / totalSupply);

    // Construct the position key
    bytes32 positionKey = PositionKey.compute(address(this), tickLower, tickUpper);

    // Fetch the position information
    (, , , , , , , uint128 liquidity,,,) = nonfungiblePositionManager.positions(positionKey);

    // Ensure that the calculated liquidity to burn is not greater than the position's liquidity
    require(liquidityToBurn <= liquidity, "Insufficient liquidity to burn");

    // Burn the liquidity share
    nonfungiblePositionManager.decreaseLiquidity(
        INonfungiblePositionManager.DecreaseLiquidityParams({
            tokenId: uint256(positionKey),
            liquidity: liquidityToBurn,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
         })
       );

    // Emit an event or perform any necessary actions after burning the liquidity share
    emit LiquidityShareBurned(tickLower, tickUpper, shares, liquidityToBurn);
    }

    function rebalance() external nonReentrant {
    // Fetch the current price range of the Ambient pool
    (int24 currentTickLower, int24 currentTickUpper, , , , , ) = getCurrentTickRange();

    // Place full-range order
    placeFullRangeOrder(currentTickLower, currentTickUpper);

    // Place base order
    placeBaseOrder(currentTickLower, currentTickUpper);

    // Place limit order
    placeLimitOrder(currentTickLower, currentTickUpper);

    // Emit an event or perform any necessary actions after rebalancing
    emit Rebalanced(currentTickLower, currentTickUpper);
    }

    function getCurrentTickRange() internal view returns (int24, int24) {
    // Fetch the current tick range from the pool or use any other method to determine the range
    // For example:
    // int24 currentTickLower = ...;
    // int24 currentTickUpper = ...;
    // return (currentTickLower, currentTickUpper);
    }

    function placeFullRangeOrder(int24 currentTickLower, int24 currentTickUpper) internal {
    // Place a full-range order on the pool
    // Use Ambient SDK or any other method to place the order
    }

    function placeBaseOrder(int24 currentTickLower, int24 currentTickUpper) internal {
    // Place a base order on the pool
    // Use Ambient SDK or any other method to place the order
    }

    function placeLimitOrder(int24 currentTickLower, int24 currentTickUpper) internal {
    // Place a limit order on the pool
    // Use Ambient SDK or any other method to place the order
    }


   function checkCanRebalance() public view {
    require(canRebalanceByTime(), "Not enough time has passed since the last rebalance");
    require(canRebalanceByPriceMovement(), "Price has not moved enough to trigger rebalance");
    require(isPriceNearTWAP(), "Price is not near the time-weighted average price (TWAP)");
    require(isPriceNotTooCloseToBoundary(), "Price is too close to the boundary");

    // If all checks pass, the vault can safely rebalance
   }

    function canRebalanceByTime() internal view returns (bool) {
    // Implement logic to check if enough time has passed since the last rebalance
    // For example:
    // return block.timestamp >= lastRebalanceTimestamp + rebalanceInterval;
    }

    function canRebalanceByPriceMovement() internal view returns (bool) {
    // Implement logic to check if the price has moved enough to trigger rebalance
    // For example:
    // return abs(currentPrice - lastRebalancePrice) >= minPriceMovement;
    }

    function isPriceNearTWAP() internal view returns (bool) {
    // Implement logic to check if the price is near the time-weighted average price (TWAP)
    // For example:
    // return abs(currentPrice - TWAP) <= maxTWAPDeviation;
    }

    function isPriceNotTooCloseToBoundary() internal view returns (bool) {
    // Implement logic to check if the price is not too close to the boundary
    // For example:
    // return abs(currentTick - boundaryTick) > minTickDistanceToBoundary;
    }

    function getTwap() public view returns (int24) {
    int24 twap = fetchTwapFromPool();
    return twap;
    }

    function fetchTwapFromPool() internal view returns (int24) {
    // Call the Ambient pool contract to fetch the TWAP
    // For example:
    // int24 twap = ambientPool.getTwap();
    // return twap;

    // Placeholder return value for demonstration
    return 0;
    }

    function _floor(int24 tick) internal view returns (int24) {
    int24 roundedTick = tick / tickSpacing * tickSpacing;
    return roundedTick;
    }


    function _checkThreshold(int24 threshold, int24 _tickSpacing) internal pure {
    require(threshold % _tickSpacing == 0, "Threshold must be a multiple of tickSpacing");
    // Additional validation logic can be added if needed
    }

    function _burnAndCollect(int24 tickLower, int24 tickUpper, uint128 liquidity) internal {
    INonfungiblePositionManager.Position memory position = INonfungiblePositionManager.Position({
        tokenId: 0, // Assuming tokenId 0 is used for this operation
        tickLower: tickLower,
        tickUpper: tickUpper,
        liquidity: liquidity,
        feeGrowthInside0LastX128: 0,
        feeGrowthInside1LastX128: 0,
        tokensOwed0: 0,
        tokensOwed1: 0
        });

        // Burn liquidity from the specified range
        nonfungiblePositionManager.decreaseLiquidity(position, liquidity, 0, 0, block.timestamp);

        // Collect all fees accrued during the burn
        nonfungiblePositionManager.collect(position, address(this), type(uint128).max, type(uint128).max);
    }

    function _mintLiquidity(int24 tickLower, int24 tickUpper, uint128 liquidity) internal {
    INonfungiblePositionManager.Position memory position = INonfungiblePositionManager.Position({
        tokenId: 0, // Assuming tokenId 0 is used for this operation
        tickLower: tickLower,
        tickUpper: tickUpper,
        liquidity: liquidity,
        feeGrowthInside0LastX128: 0,
        feeGrowthInside1LastX128: 0,
        tokensOwed0: 0,
        tokensOwed1: 0
    });

    // Mint liquidity into the specified range
    nonfungiblePositionManager.mint(address(this), position, liquidity, 0, 0);

    // Ensure that the tokens owed are correctly updated
    position = nonfungiblePositionManager.positions(0);
    uint128 tokensOwed0 = position.tokensOwed0;
    uint128 tokensOwed1 = position.tokensOwed1;
    }

    function getTotalAmounts() public view returns (uint256 totalAmount0, uint256 totalAmount1) {
        // Get the current position of the vault
        INonfungiblePositionManager.Position memory position = nonfungiblePositionManager.positions(0);

        // Calculate the amounts of token0 and token1 held in the position
        (uint256 positionAmount0, uint256 positionAmount1) = getPositionAmounts(position.tickLower, position.tickUpper);

        // Add the position amounts to the total
        totalAmount0 += positionAmount0;
        totalAmount1 += positionAmount1;

        // Add any unused balances in the contract
        totalAmount0 += IERC20(token0).balanceOf(address(this));
        totalAmount1 += IERC20(token1).balanceOf(address(this));

        return (totalAmount0, totalAmount1);
    }

    function getPositionAmounts(int24 tickLower, int24 tickUpper) public view returns (uint256 positionAmount0, uint256 positionAmount1) {
    // Get the current position of the vault
    INonfungiblePositionManager.Position memory position = nonfungiblePositionManager.positions(0);

    // Calculate the amounts of token0 and token1 in the position
    (uint128 liquidity, , , , , , uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , , ) =
        nonfungiblePositionManager.positions(position.id);

    // Calculate the amount of token0 and token1 owed as fees
    (uint256 collectedFee0, uint256 collectedFee1) = calculateCollectedFees(
        tickLower,
        tickUpper,
        feeGrowthInside0LastX128,
        feeGrowthInside1LastX128
    );

    // Subtract the collected fees from the total amounts
    positionAmount0 = position.token0Amount - collectedFee0;
    positionAmount1 = position.token1Amount - collectedFee1;

    return (positionAmount0, positionAmount1);
    }

    function calculateCollectedFees(
    int24 tickLower,
    int24 tickUpper,
    uint256 feeGrowthInside0LastX128,
    uint256 feeGrowthInside1LastX128
    )
     internal view returns (uint256 collectedFee0, uint256 collectedFee1) {
    // Calculate fee growth in the given tick range
    uint256 feeGrowth0 = nonfungiblePositionManager.collectableFeeGrowth(
        position.id,
        tickLower,
        tickUpper,
        feeGrowthInside0LastX128
        );
    uint256 feeGrowth1 = nonfungiblePositionManager.collectableFeeGrowth(
        position.id,
        tickLower,
        tickUpper,
        feeGrowthInside1LastX128
    );

    // Calculate fees owed in token0 and token1
    collectedFee0 = (feeGrowth0 * position.token0Amount) >> 128;
    collectedFee1 = (feeGrowth1 * position.token1Amount) >> 128;

    return (collectedFee0, collectedFee1);
    }

}
