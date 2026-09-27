// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev Test-only independent base64 decoder, so metadata tests inspect the encoded content.
library DataURI {
    function decode(string memory uri, string memory prefix) internal pure returns (bytes memory output) {
        bytes memory data = bytes(uri);
        bytes memory head = bytes(prefix);
        require(data.length > head.length, "empty data URI");
        for (uint256 i; i < head.length; ++i) {
            require(data[i] == head[i], "wrong data URI prefix");
        }
        uint256 size = data.length - head.length;
        require(size % 4 == 0, "base64 length");
        uint256 padding = data[data.length - 1] == "=" ? 1 : 0;
        if (data[data.length - 2] == "=") ++padding;
        output = new bytes(size / 4 * 3 - padding);
        uint256 cursor;
        for (uint256 i = head.length; i < data.length; i += 4) {
            uint256 word = (_digit(data[i]) << 18) | (_digit(data[i + 1]) << 12) | (_digit(data[i + 2]) << 6)
                | _digit(data[i + 3]);
            if (cursor < output.length) output[cursor++] = bytes1(uint8(word >> 16));
            if (cursor < output.length) output[cursor++] = bytes1(uint8(word >> 8));
            if (cursor < output.length) output[cursor++] = bytes1(uint8(word));
        }
    }

    function contains(string memory value, string memory needle) internal pure returns (bool) {
        bytes memory haystack = bytes(value);
        bytes memory query = bytes(needle);
        if (query.length > haystack.length) return false;
        for (uint256 i; i <= haystack.length - query.length; ++i) {
            bool match_ = true;
            for (uint256 j; j < query.length; ++j) {
                if (haystack[i + j] != query[j]) {
                    match_ = false;
                    break;
                }
            }
            if (match_) return true;
        }
        return false;
    }

    function _digit(bytes1 value) private pure returns (uint256) {
        uint8 char = uint8(value);
        if (char >= 65 && char <= 90) return char - 65;
        if (char >= 97 && char <= 122) return char - 71;
        if (char >= 48 && char <= 57) return char + 4;
        if (value == "+") return 62;
        if (value == "/") return 63;
        require(value == "=", "base64 character");
        return 0;
    }
}
