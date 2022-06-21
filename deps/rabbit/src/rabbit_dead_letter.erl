%% This Source Code Form is subject to the terms of the Mozilla Public
%% License, v. 2.0. If a copy of the MPL was not distributed with this
%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%
%% Copyright (c) 2007-2023 VMware, Inc. or its affiliates.  All rights reserved.
%%

-module(rabbit_dead_letter).

-export([publish/5,
         detect_cycles/3]).

-include_lib("rabbit_common/include/rabbit.hrl").

%%----------------------------------------------------------------------------

-type reason() :: 'expired' | 'rejected' | 'maxlen' | delivery_limit.
-export_type([reason/0]).

%%----------------------------------------------------------------------------

-spec publish(mc:state(), reason(), rabbit_types:exchange(),
              undefined | binary(), rabbit_amqqueue:name()) ->
    ok.
publish(Msg00, Reason, #exchange{name = XName} = DLX, RK,
        #resource{name = SourceQName}) ->

    DLRKeys = case RK of
                  undefined ->
                      mc:get_annotation(routing_keys, Msg00);
                  _ ->
                      [RK]
              end,

    Msg0 = mc:record_death(Reason, SourceQName, Msg00),
    Msg1 = mc:set_ttl(undefined, Msg0),
    Msg2 = mc:set_annotation(routing_keys, DLRKeys, Msg1),
    DLMsg = mc:set_annotation(exchange, XName#resource.name, Msg2),
    Routed = rabbit_exchange:route(DLX, DLMsg),
    {QNames, Cycles} = detect_cycles(Reason, DLMsg, Routed),
    lists:foreach(fun log_cycle_once/1, Cycles),
    Qs0 = rabbit_amqqueue:lookup_many(QNames),
    Qs = rabbit_amqqueue:prepend_extra_bcc(Qs0),
    _ = rabbit_queue_type:deliver(Qs, DLMsg, #{}, stateless),
    ok.

detect_cycles(rejected, _Msg, Queues) ->
    {Queues, []};
detect_cycles(_Reason, Msg, Queues) ->
    {Cycling, NotCycling} =
        lists:partition(fun (#resource{name = Queue}) ->
                                mc:is_death_cycle(Queue, Msg);
                            (_) ->
                                false
                        end, Queues),
    DeathQueues = mc:death_queue_names(Msg),
    CycleKeys = [[Q | DeathQueues] || #resource{name = Q} <- Cycling],
    {NotCycling, CycleKeys}.

log_cycle_once(Queues) ->
    %% using a hash won't eliminate this as a potential memory leak but it will
    %% reduce the potential amount of memory used whilst probably being
    %% "good enough"
    Key = {queue_cycle, erlang:phash2(Queues)},
    case get(Key) of
        true -> ok;
        undefined ->
            rabbit_log:warning("Message dropped. Dead-letter queues cycle detected"
                               ": ~tp~nThis cycle will NOT be reported again.",
                               [Queues]),
            put(Key, true)
    end.
