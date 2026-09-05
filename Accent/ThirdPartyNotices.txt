# Third-party notices

Accent's original code is MIT licensed. The following components retain their
own licenses; the MIT license does not relicense them.

## MultiBridge phoneme recognizer and labels

Source: https://huggingface.co/MultiBridge/wav2vec-LnNor-IPA-ft
Creator: MultiBridge (model-card authors Agnieszka Pludra, Izabela Krysińska,
and Piotr Kabaciński).
License: Creative Commons Attribution 4.0 International (CC BY 4.0):
https://creativecommons.org/licenses/by/4.0/
Legal text: https://creativecommons.org/licenses/by/4.0/legalcode

Accent converts the checkpoint to an FP16 Core ML program and exports its IPA
vocabulary/preprocessing metadata into `Accent/phoneme_labels.json`. These are
format/precision changes, not a new training run. The converted model weights
are not committed. Preserve this attribution and the license link when
redistributing the model or derived labels. No endorsement is implied.

The upstream model card cautions that canonical rather than actual pronunciation
labels in part of its training data may impair non-native speech assessment.
Evaluate it for your users; this project does not establish clinical or perceptual
accuracy. Upstream training datasets are not redistributed here.

## CMU Pronouncing Dictionary

`Accent/cmudict.txt` is derived from CMUdict:
https://github.com/cmusphinx/cmudict
License source: https://github.com/cmusphinx/cmudict/blob/master/LICENSE

Copyright (C) 1993-2015 Carnegie Mellon University. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
   The contents of this file are deemed to be source code.

2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in
   the documentation and/or other materials provided with the
   distribution.

This work was supported in part by funding from the Defense Advanced
Research Projects Agency, the Office of Naval Research and the National
Science Foundation of the United States of America, and by member
companies of the Carnegie Mellon Sphinx Speech Consortium. We acknowledge
the contributions of many volunteers to the expansion and improvement of
this dictionary.

THIS SOFTWARE IS PROVIDED BY CARNEGIE MELLON UNIVERSITY ``AS IS'' AND
ANY EXPRESSED OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL CARNEGIE MELLON UNIVERSITY
NOR ITS EMPLOYEES BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
