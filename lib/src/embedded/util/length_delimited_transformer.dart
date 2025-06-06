// Copyright 2019 Google Inc. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:stream_channel/stream_channel.dart';

import '../utils.dart';
import 'varint_builder.dart';

/// A [StreamChannelTransformer] that converts a channel that sends and receives
/// arbitrarily-chunked binary data to one that sends and receives packets of
/// set length using [lengthDelimitedEncoder] and [lengthDelimitedDecoder].
final StreamChannelTransformer<Uint8List, List<int>> lengthDelimited =
    StreamChannelTransformer<Uint8List, List<int>>(
  lengthDelimitedDecoder,
  StreamSinkTransformer.fromStreamTransformer(lengthDelimitedEncoder),
);

/// A transformer that converts an arbitrarily-chunked byte stream where each
/// packet is prefixed with a 32-bit little-endian number indicating its length
/// into a stream of packet contents.
final lengthDelimitedDecoder =
    StreamTransformer<List<int>, Uint8List>.fromBind((stream) {
  // The builder for the varint indicating the length of the next message.
  //
  // Once this is fully built up, [buffer] is initialized and this is reset.
  final nextMessageLengthBuilder = VarintBuilder(53, 'packet length');

  // The buffer into which the packet data itself is written. Initialized once
  // [nextMessageLength] is known.
  Uint8List? buffer;

  // The index of the next byte to write to [buffer]. Once this is equal to
  // [buffer.length] (or equivalently [nextMessageLength]), the full packet is
  // available.
  var bufferIndex = 0;

  // It seems a little silly to use a nested [StreamTransformer] here, but we
  // need the outer one to establish a closure context so we can share state
  // across different input chunks, and the inner one takes care of all the
  // boilerplate of creating a new stream based on [stream].
  return stream.transform(
    StreamTransformer.fromHandlers(
      handleData: (chunk, sink) {
        // The index of the next byte to read from [chunk]. We have to track this
        // because the chunk may contain the length *and* the message, or even
        // multiple messages.
        var i = 0;

        while (i < chunk.length) {
          var buffer_ = buffer; // dart-lang/language#1536

          // We can be in one of two states here:
          //
          // * [buffer] is `null`, in which case we're adding data to
          //   [nextMessageLength] until we reach a byte with its most significant
          //   bit set to 0.
          //
          // * [buffer] is not `null`, in which case we're waiting for [buffer] to
          //   have [nextMessageLength] bytes in it before we send it to
          //   [queue.local.sink] and start waiting for the next message.
          if (buffer_ == null) {
            var length = nextMessageLengthBuilder.add(chunk[i]);
            i++;
            if (length == null) continue;

            // Otherwise, [nextMessageLength] is now finalized and we can allocate
            // the data buffer.
            buffer_ = buffer = Uint8List(length);
            bufferIndex = 0;
          }

          // Copy as many bytes as we can from [chunk] to [buffer], making sure not
          // to try to copy more than the buffer can hold (if the chunk has another
          // message after the current one) or more than the chunk has available (if
          // the current message is split across multiple chunks).
          var bytesToWrite = math.min(
            buffer_.length - bufferIndex,
            chunk.length - i,
          );
          buffer_.setRange(bufferIndex, bufferIndex + bytesToWrite, chunk, i);
          i += bytesToWrite;
          bufferIndex += bytesToWrite;
          if (bufferIndex < buffer_.length) return;

          // Once we've filled the buffer, emit it and reset our state.
          sink.add(buffer_);
          nextMessageLengthBuilder.reset();
          buffer = null;
        }
      },
    ),
  );
});

/// A transformer that adds 32-bit little-endian numbers indicating the length
/// of each packet, so that they can safely be sent over a medium that doesn't
/// preserve packet boundaries.
final lengthDelimitedEncoder =
    StreamTransformer<Uint8List, List<int>>.fromHandlers(
  handleData: (message, sink) {
    var length = message.length;
    if (length == 0) {
      sink.add([0]);
      return;
    }

    sink.add(serializeVarint(length));
    sink.add(message);
  },
);
