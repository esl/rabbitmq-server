%% This Source Code Form is subject to the terms of the Mozilla Public
%% License, v. 2.0. If a copy of the MPL was not distributed with this
%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%
%% Copyright (c) 2007-2023 VMware, Inc. or its affiliates.  All rights reserved.
%%

-module(esl_amqp_shovel_dyn_worker_sup).
-behaviour(supervisor2).

-export([start_link/2, init/1]).

-import(rabbit_misc, [pget/3]).

-include_lib("rabbit_common/include/rabbit.hrl").
-include("esl_amqp_shovel.hrl").
-define(SUPERVISOR, ?MODULE).

start_link(Name, Config) ->
    ShovelParameter = esl_amqp_shovel_util:get_shovel_parameter(Name),
    maybe_start_link(ShovelParameter, Name, Config).

maybe_start_link(not_found, _Name, _Config) ->
    %% See rabbitmq/rabbitmq-server#2655.
    %% All dynamic shovels require that their associated parameter is present.
    %% If not, this shovel has been deleted and stale child spec information
    %% may still reside in the supervisor.
    %%
    %% We return 'ignore' to ensure that the child is not [re-]added in such case.
    ignore;
maybe_start_link(_, Name, Config) ->
    supervisor2:start_link(?MODULE, [Name, Config]).

%%----------------------------------------------------------------------------

init([Name, Config0]) ->
    Config  = rabbit_data_coercion:to_proplist(Config0),
    Delay   = pget(<<"reconnect-delay">>, Config, ?DEFAULT_RECONNECT_DELAY),
    case Name of
      {VHost, ShovelName} -> rabbit_log:debug("Shovel '~ts' in virtual host '~ts' will use reconnection delay of ~tp", [ShovelName, VHost, Delay]);
      ShovelName          -> rabbit_log:debug("Shovel '~ts' will use reconnection delay of ~ts", [ShovelName, Delay])
    end,
    Restart = case Delay of
        N when is_integer(N) andalso N > 0 ->
          case pget(<<"src-delete-after">>, Config, pget(<<"delete-after">>, Config, <<"never">>)) of
            %% always try to reconnect
            <<"never">>                        -> {permanent, N};
            %% this Shovel is an autodelete one
              M when is_integer(M) andalso M >= 0 -> {transient, N};
              <<"queue-length">> -> {transient, N}
          end;
        %% reconnect-delay = 0 means "do not reconnect"
        _                                  -> temporary
    end,
    {ok, {{one_for_one, 1, ?MAX_WAIT},
          [{Name,
            {esl_amqp_shovel_worker, start_link, [dynamic, Name, Config]},
            Restart,
            16#ffffffff, worker, [esl_amqp_shovel_worker]}]}}.
