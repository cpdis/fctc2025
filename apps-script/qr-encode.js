'use strict';

/**
 * Small QR encoder for UTF-8 byte-mode setup payloads.
 *
 * This is a purpose-built CommonJS subset of Project Nayuki's public-domain
 * QR Code generator algorithm: https://www.nayuki.io/page/qr-code-generator-library
 * It supports versions 1 through 14 at error-correction level M. That covers
 * setup payloads up to 331 bytes while keeping the release tool dependency-free.
 * (A production /exec URL plus a strong secret is ~250 bytes, which overflowed
 * the original version-10 ceiling of 213 on the first real deploy.)
 */

const MIN_VERSION = 1;
const MAX_VERSION = 14;
const FORMAT_BITS_MEDIUM = 0;

// Index zero is unused, matching QR version numbers directly. Values are the
// spec's error-correction-level-M rows, as in Nayuki's reference tables.
const ECC_CODEWORDS_PER_BLOCK = [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24];
const NUM_ERROR_CORRECTION_BLOCKS = [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9];

function encodeText(text, options = {}) {
  if (typeof text !== 'string') throw new TypeError('QR input must be text.');
  const bytes = Array.from(Buffer.from(text, 'utf8'));
  const version = chooseVersion(bytes.length);
  const dataCodewords = makeDataCodewords(bytes, version);
  const allCodewords = addErrorCorrectionAndInterleave(dataCodewords, version);
  const qr = new QRMatrix(version);
  qr.drawFunctionPatterns();
  qr.drawCodewords(allCodewords);

  const forcedMask = options.mask;
  const mask = forcedMask === undefined ? qr.chooseMask() : validateMask(forcedMask);
  qr.applyMask(mask);
  qr.drawFormatBits(mask);

  return {
    version,
    size: qr.size,
    mask,
    matrix: cloneMatrix(qr.modules),
    functionModules: cloneMatrix(qr.isFunction),
  };
}

function chooseVersion(byteLength) {
  for (let version = MIN_VERSION; version <= MAX_VERSION; version += 1) {
    const countBits = version <= 9 ? 8 : 16;
    if (byteLength >= (1 << countBits)) continue;
    const usedBits = 4 + countBits + byteLength * 8;
    if (usedBits <= getNumDataCodewords(version) * 8) return version;
  }
  throw new RangeError('Setup payload is too long for this QR encoder. Shorten the URL, secret, or device name.');
}

function makeDataCodewords(bytes, version) {
  const capacity = getNumDataCodewords(version) * 8;
  const bits = [];
  appendBits(0x4, 4, bits); // Byte mode.
  appendBits(bytes.length, version <= 9 ? 8 : 16, bits);
  for (const byte of bytes) appendBits(byte, 8, bits);
  appendBits(0, Math.min(4, capacity - bits.length), bits);
  while (bits.length % 8 !== 0) bits.push(0);

  const result = [];
  for (let i = 0; i < bits.length; i += 8) {
    let value = 0;
    for (let j = 0; j < 8; j += 1) value = (value << 1) | bits[i + j];
    result.push(value);
  }
  for (let pad = 0xEC; result.length < capacity / 8; pad ^= 0xEC ^ 0x11) {
    result.push(pad);
  }
  return result;
}

function addErrorCorrectionAndInterleave(data, version) {
  const numberOfBlocks = NUM_ERROR_CORRECTION_BLOCKS[version];
  const blockEccLength = ECC_CODEWORDS_PER_BLOCK[version];
  const rawCodewords = Math.floor(getNumRawDataModules(version) / 8);
  const shortBlockCount = numberOfBlocks - (rawCodewords % numberOfBlocks);
  const shortBlockLength = Math.floor(rawCodewords / numberOfBlocks);
  const divisor = reedSolomonDivisor(blockEccLength);
  const blocks = [];
  let offset = 0;

  for (let block = 0; block < numberOfBlocks; block += 1) {
    const dataLength = shortBlockLength - blockEccLength
      + (block < shortBlockCount ? 0 : 1);
    const blockData = data.slice(offset, offset + dataLength);
    offset += dataLength;
    const ecc = reedSolomonRemainder(blockData, divisor);
    if (block < shortBlockCount) blockData.push(0); // Interleave alignment only.
    blocks.push(blockData.concat(ecc));
  }
  if (offset !== data.length) throw new Error('QR block split did not consume all data.');

  const result = [];
  for (let index = 0; index < blocks[0].length; index += 1) {
    for (let block = 0; block < blocks.length; block += 1) {
      if (index === shortBlockLength - blockEccLength && block < shortBlockCount) continue;
      result.push(blocks[block][index]);
    }
  }
  if (result.length !== rawCodewords) throw new Error('QR interleave produced the wrong length.');
  return result;
}

class QRMatrix {
  constructor(version) {
    this.version = version;
    this.size = version * 4 + 17;
    this.modules = square(this.size, false);
    this.isFunction = square(this.size, false);
  }

  drawFunctionPatterns() {
    for (let i = 0; i < this.size; i += 1) {
      this.setFunction(6, i, i % 2 === 0);
      this.setFunction(i, 6, i % 2 === 0);
    }
    this.drawFinder(3, 3);
    this.drawFinder(this.size - 4, 3);
    this.drawFinder(3, this.size - 4);

    const positions = alignmentPatternPositions(this.version);
    for (let i = 0; i < positions.length; i += 1) {
      for (let j = 0; j < positions.length; j += 1) {
        const isFinderCorner = (i === 0 && j === 0)
          || (i === 0 && j === positions.length - 1)
          || (i === positions.length - 1 && j === 0);
        if (!isFinderCorner) this.drawAlignment(positions[i], positions[j]);
      }
    }
    this.drawFormatBits(0);
    this.drawVersion();
  }

  drawFinder(centerX, centerY) {
    for (let dy = -4; dy <= 4; dy += 1) {
      for (let dx = -4; dx <= 4; dx += 1) {
        const x = centerX + dx;
        const y = centerY + dy;
        if (x < 0 || y < 0 || x >= this.size || y >= this.size) continue;
        const distance = Math.max(Math.abs(dx), Math.abs(dy));
        this.setFunction(x, y, distance !== 2 && distance !== 4);
      }
    }
  }

  drawAlignment(centerX, centerY) {
    for (let dy = -2; dy <= 2; dy += 1) {
      for (let dx = -2; dx <= 2; dx += 1) {
        this.setFunction(centerX + dx, centerY + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
      }
    }
  }

  drawFormatBits(mask) {
    const data = (FORMAT_BITS_MEDIUM << 3) | mask;
    let remainder = data;
    for (let i = 0; i < 10; i += 1) {
      remainder = (remainder << 1) ^ (((remainder >>> 9) & 1) * 0x537);
    }
    const bits = ((data << 10) | remainder) ^ 0x5412;
    const bit = (index) => ((bits >>> index) & 1) !== 0;

    for (let i = 0; i <= 5; i += 1) this.setFunction(8, i, bit(i));
    this.setFunction(8, 7, bit(6));
    this.setFunction(8, 8, bit(7));
    this.setFunction(7, 8, bit(8));
    for (let i = 9; i < 15; i += 1) this.setFunction(14 - i, 8, bit(i));

    for (let i = 0; i < 8; i += 1) this.setFunction(this.size - 1 - i, 8, bit(i));
    for (let i = 8; i < 15; i += 1) this.setFunction(8, this.size - 15 + i, bit(i));
    this.setFunction(8, this.size - 8, true);
  }

  drawVersion() {
    if (this.version < 7) return;
    let remainder = this.version;
    for (let i = 0; i < 12; i += 1) {
      remainder = (remainder << 1) ^ (((remainder >>> 11) & 1) * 0x1F25);
    }
    const bits = (this.version << 12) | remainder;
    for (let i = 0; i < 18; i += 1) {
      const dark = ((bits >>> i) & 1) !== 0;
      const a = this.size - 11 + (i % 3);
      const b = Math.floor(i / 3);
      this.setFunction(a, b, dark);
      this.setFunction(b, a, dark);
    }
  }

  drawCodewords(codewords) {
    let bitIndex = 0;
    for (let right = this.size - 1; right >= 1; right -= 2) {
      if (right === 6) right = 5;
      for (let vertical = 0; vertical < this.size; vertical += 1) {
        const upward = ((right + 1) & 2) === 0;
        const y = upward ? this.size - 1 - vertical : vertical;
        for (let column = 0; column < 2; column += 1) {
          const x = right - column;
          if (this.isFunction[y][x] || bitIndex >= codewords.length * 8) continue;
          this.modules[y][x] = ((codewords[bitIndex >>> 3] >>> (7 - (bitIndex & 7))) & 1) !== 0;
          bitIndex += 1;
        }
      }
    }
    if (bitIndex !== codewords.length * 8) throw new Error('QR matrix did not consume all codeword bits.');
  }

  chooseMask() {
    let bestMask = 0;
    let bestPenalty = Infinity;
    for (let mask = 0; mask < 8; mask += 1) {
      this.applyMask(mask);
      this.drawFormatBits(mask);
      const penalty = penaltyScore(this.modules);
      if (penalty < bestPenalty) {
        bestPenalty = penalty;
        bestMask = mask;
      }
      this.applyMask(mask);
    }
    return bestMask;
  }

  applyMask(mask) {
    validateMask(mask);
    for (let y = 0; y < this.size; y += 1) {
      for (let x = 0; x < this.size; x += 1) {
        if (!this.isFunction[y][x] && maskCondition(mask, x, y)) {
          this.modules[y][x] = !this.modules[y][x];
        }
      }
    }
  }

  setFunction(x, y, dark) {
    this.modules[y][x] = dark;
    this.isFunction[y][x] = true;
  }
}

function alignmentPatternPositions(version) {
  if (version === 1) return [];
  const count = Math.floor(version / 7) + 2;
  const step = Math.ceil((version * 4 + count * 2 + 1) / (count * 2 - 2)) * 2;
  const result = [6];
  for (let position = version * 4 + 10; result.length < count; position -= step) {
    result.splice(1, 0, position);
  }
  return result;
}

function maskCondition(mask, x, y) {
  switch (mask) {
    case 0: return (x + y) % 2 === 0;
    case 1: return y % 2 === 0;
    case 2: return x % 3 === 0;
    case 3: return (x + y) % 3 === 0;
    case 4: return (Math.floor(y / 2) + Math.floor(x / 3)) % 2 === 0;
    case 5: return ((x * y) % 2) + ((x * y) % 3) === 0;
    case 6: return (((x * y) % 2) + ((x * y) % 3)) % 2 === 0;
    case 7: return (((x + y) % 2) + ((x * y) % 3)) % 2 === 0;
    default: throw new RangeError('QR mask must be between 0 and 7.');
  }
}

function penaltyScore(modules) {
  const size = modules.length;
  let result = 0;
  for (let y = 0; y < size; y += 1) result += linePenalty(modules[y]);
  for (let x = 0; x < size; x += 1) {
    result += linePenalty(modules.map((row) => row[x]));
  }

  for (let y = 0; y < size - 1; y += 1) {
    for (let x = 0; x < size - 1; x += 1) {
      const color = modules[y][x];
      if (modules[y][x + 1] === color
          && modules[y + 1][x] === color
          && modules[y + 1][x + 1] === color) result += 3;
    }
  }

  const dark = modules.reduce((sum, row) => sum + row.filter(Boolean).length, 0);
  result += Math.floor(Math.abs(dark * 20 - size * size * 10) / (size * size)) * 10;
  return result;
}

function linePenalty(line) {
  let result = 0;
  let runLength = 1;
  for (let i = 1; i < line.length; i += 1) {
    if (line[i] === line[i - 1]) {
      runLength += 1;
      if (runLength === 5) result += 3;
      else if (runLength > 5) result += 1;
    } else {
      runLength = 1;
    }
  }

  const bits = line.map((value) => (value ? '1' : '0')).join('');
  for (let offset = 0; offset <= bits.length - 11; offset += 1) {
    const pattern = bits.slice(offset, offset + 11);
    if (pattern === '00001011101' || pattern === '10111010000') result += 40;
  }
  return result;
}

function reedSolomonDivisor(degree) {
  const result = Array(degree).fill(0);
  result[degree - 1] = 1;
  let root = 1;
  for (let i = 0; i < degree; i += 1) {
    for (let j = 0; j < result.length; j += 1) {
      result[j] = reedSolomonMultiply(result[j], root);
      if (j + 1 < result.length) result[j] ^= result[j + 1];
    }
    root = reedSolomonMultiply(root, 0x02);
  }
  return result;
}

function reedSolomonRemainder(data, divisor) {
  const result = Array(divisor.length).fill(0);
  for (const byte of data) {
    const factor = byte ^ result.shift();
    result.push(0);
    for (let i = 0; i < divisor.length; i += 1) {
      result[i] ^= reedSolomonMultiply(divisor[i], factor);
    }
  }
  return result;
}

function reedSolomonMultiply(left, right) {
  let x = left;
  let y = right;
  let result = 0;
  while (y !== 0) {
    if ((y & 1) !== 0) result ^= x;
    y >>>= 1;
    x <<= 1;
    if ((x & 0x100) !== 0) x ^= 0x11D;
  }
  return result;
}

function getNumDataCodewords(version) {
  return Math.floor(getNumRawDataModules(version) / 8)
    - ECC_CODEWORDS_PER_BLOCK[version] * NUM_ERROR_CORRECTION_BLOCKS[version];
}

function getNumRawDataModules(version) {
  if (version < MIN_VERSION || version > MAX_VERSION) throw new RangeError('Unsupported QR version.');
  let result = (16 * version + 128) * version + 64;
  if (version >= 2) {
    const align = Math.floor(version / 7) + 2;
    result -= (25 * align - 10) * align - 55;
    if (version >= 7) result -= 36;
  }
  return result;
}

function appendBits(value, length, target) {
  if (length < 0 || length > 31 || value >>> length !== 0) {
    throw new RangeError('Value does not fit in the requested bit length.');
  }
  for (let i = length - 1; i >= 0; i -= 1) target.push((value >>> i) & 1);
}

function validateMask(mask) {
  if (!Number.isInteger(mask) || mask < 0 || mask > 7) {
    throw new RangeError('QR mask must be between 0 and 7.');
  }
  return mask;
}

function square(size, value) {
  return Array.from({ length: size }, () => Array(size).fill(value));
}

function cloneMatrix(matrix) {
  return matrix.map((row) => row.slice());
}

module.exports = {
  encodeText,
  maskCondition,
};
