#if defined _arena_included
  #endinput
#endif
#define _arena_included

/*
 * Retorna el tiempo restante para que termine la ronda
 */
native ar_get_round_time( );

/*
 * Retorna la arena en la que se encuentra el jugador
 */
native ar_get_player_arena( const iPlayer );