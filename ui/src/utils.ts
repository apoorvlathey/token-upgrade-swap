import { BigNumber } from "@ethersproject/bignumber";

export const slicedAddress = (address: string) => {
  return `${address.slice(0, 6)}...${address.slice(
    address.length - 4,
    address.length
  )}`;
};

export const toDecimal = (amount: BigNumber | string, decimals: number) => {
  let amountInString = amount.toString();
  if (amountInString.length <= decimals) {
    const pad = Array(decimals + 1 - amountInString.length + 1).join("0");
    amountInString = pad + amountInString;
  }

  const beforeDecimal = amountInString.slice(0, -decimals);
  const afterDecimal = amountInString.slice(-decimals).replace(/0+$/, ""); // replaces trailing zeroes
  let output =
    afterDecimal.length > 0
      ? beforeDecimal + "." + afterDecimal
      : beforeDecimal;

  return output;
};

export const numberWithCommas = (x: string | number | BigNumber) => {
  return x.toString().replace(/\B(?<!\.\d*)(?=(\d{3})+(?!\d))/g, ",");
};

export const formatNumber = (
  number: BigNumber | string,
  decimals: number = 18
) => {
  if (decimals === 0) {
    return numberWithCommas(number.toString());
  }

  return numberWithCommas(parseFloat(toDecimal(number, decimals)).toFixed(4));
};
