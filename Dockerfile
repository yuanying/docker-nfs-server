# Copyright 2016 The Kubernetes Authors.
# Copyright 2018 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

FROM debian:12

ADD index.html /tmp/index.html
RUN chmod 644 /tmp/index.html

ENV C2D_RELEASE 1.3.4

RUN set -x && \
    apt-get update && apt-get install -qq -y openssl nfs-kernel-server && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir /exports

COPY entrypoint.sh /usr/local/bin/
RUN chmod +rx /usr/local/bin/entrypoint.sh

VOLUME /exports

EXPOSE 2049/tcp
EXPOSE 20048/tcp

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/exports"]
