%% This Source Code Form is subject to the terms of the Mozilla Public
%% License, v. 2.0. If a copy of the MPL was not distributed with this
%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%
%% Copyright (c) 2007-2023 VMware, Inc. or its affiliates.  All rights reserved.
%%

-module(esl_amqp_shovel).

-export([start/0, stop/0, start/2, stop/1]).

start() ->
    _ = esl_amqp_shovel_sup:start_link(),
    ok.

stop() -> ok.

start(normal, []) ->
    esl_amqp_shovel_sup:start_link().

stop(_State) -> ok.
