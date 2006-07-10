module interp_option_module

   use gridinfo_module
   use list_module
   use misc_definitions_module
   use module_debug

   integer, parameter :: BUFSIZE=128

   integer :: num_entries
   integer, pointer, dimension(:) :: masked, output_stagger
   real, pointer, dimension(:) :: fill_missing, missing_value, interp_mask_val
   logical, pointer, dimension(:) :: output_this_field, is_u_field, is_v_field, is_derived_field
   character (len=128), pointer, dimension(:) :: fieldname, interp_method, v_interp_method, &
                  interp_mask, flag_in_output, from_input, z_dim_name
   type (list), pointer, dimension(:) :: fill_lev_list
   type (list) :: flag_in_output_list

   contains

   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   ! Name: read_interp_table
   !
   ! Purpose:
   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   subroutine read_interp_table()

      ! Local variables
      integer :: i, p1, p2, idx, eos, ispace, funit, istatus, nparams
      logical :: is_used, have_specification
      character (len=128) :: lev_string, fill_string, flag_string, flag_val
      character (len=BUFSIZE) :: buffer
   
      do funit=10,100
         inquire(unit=funit, opened=is_used)
         if (.not. is_used) exit
      end do 
   
      nparams = 0
      num_entries = 0
   
      open(funit, file=trim(opt_metgrid_tbl_path)//'METGRID.TBL', form='formatted', status='old', err=1001)
      istatus = 0
      do while (istatus == 0) 
         read(funit, '(a)', iostat=istatus) buffer
         if (istatus == 0) then
            call despace(buffer)
   
            ! Is this line a comment?
            if (buffer(1:1) == '#') then
   
            ! Are we beginning a new field specification?
            else if (index(buffer,'=====') /= 0) then
               if (nparams > 0) num_entries = num_entries + 1
               nparams = 0
   
            else
               eos = index(buffer,'#')
               if (eos /= 0) buffer(eos:BUFSIZE) = ' '
    
               ! Does this line contain at least one parameter specification?
               if (index(buffer,'=') /= 0) then
                  nparams = nparams + 1
               end if
            end if
   
         end if
      end do 
   
      rewind(funit)
   
      ! Allocate one extra array element to act as the default
! BUG: Maybe this will not be necessary if we move to a module with query routines for
!  parsing the METGRID.TBL
      num_entries = num_entries + 1
   
      allocate(fieldname(num_entries))
      allocate(interp_method(num_entries))
      allocate(v_interp_method(num_entries))
      allocate(masked(num_entries))
      allocate(fill_missing(num_entries))
      allocate(missing_value(num_entries))
      allocate(fill_lev_list(num_entries))
      allocate(interp_mask(num_entries))
      allocate(interp_mask_val(num_entries))
      allocate(flag_in_output(num_entries))
      allocate(from_input(num_entries))
      allocate(z_dim_name(num_entries))
      allocate(output_stagger(num_entries))
      allocate(output_this_field(num_entries))
      allocate(is_u_field(num_entries))
      allocate(is_v_field(num_entries))
      allocate(is_derived_field(num_entries))
   
      !
      ! Set default values
      !
      do i=1,num_entries
         fieldname(i) = ' '
         flag_in_output(i) = ' '
         from_input(i) = '*'
         z_dim_name(i) = 'num_vert_levels'
         interp_method(i) = 'nearest_neighbor'
         v_interp_method(i) = 'linear_log_p'
         masked(i) = -1
         fill_missing(i) = NAN
         missing_value(i) = NAN
         call list_init(fill_lev_list(i))
         interp_mask(i) = ' '
         interp_mask_val(i) = NAN
! BUG: Maybe default output stagger should depend on grid_type
         output_stagger(i) = M
         output_this_field(i) = .true.
         is_u_field(i) = .false.
         is_v_field(i) = .false.
         is_derived_field(i) = .false.
      end do
      call list_init(flag_in_output_list)
   
      i = 1
      istatus = 0
      nparams = 0
   
      do while (istatus == 0) 
         buffer = ' '
         read(funit, '(a)', iostat=istatus) buffer
         if (istatus == 0) then
            call despace(buffer)
   
            ! Is this line a comment?
            if (buffer(1:1) == '#') then
               ! Do nothing.
   
            ! Are we beginning a new field specification?
            else if (index(buffer,'=====') /= 0) then   !{
               if (nparams > 0) i = i + 1
               nparams = 0
   
            else
               ! Check whether the current line is a comment
               if (buffer(1:1) /= '#') then
                 have_specification = .true.
               else
                 have_specification = .false.
               end if
         
               ! If only part of the line is a comment, just turn the comment into spaces
               eos = index(buffer,'#')
               if (eos /= 0) buffer(eos:BUFSIZE) = ' '
         
               do while (have_specification)   !{
         
                  ! If this line has no semicolon, it may contain a single specification,
                  !   so we set have_specification = .false. to prevent the line from being
                  !   processed again and "pretend" that the last character was a semicolon
                  eos = index(buffer,';')
                  if (eos == 0) then
                    have_specification = .false.
                    eos = BUFSIZE
                  end if
          
                  idx = index(buffer(1:eos-1),'=')
          
                  if (idx /= 0) then   !{
                     nparams = nparams + 1
           
                     if (index('name',trim(buffer(1:idx-1))) /= 0) then
                        ispace = idx+1
                        do while ((ispace < eos) .and. (buffer(ispace:ispace) /= ' '))
                           ispace = ispace + 1
                        end do
                        fieldname(i) = ' '
                        fieldname(i)(1:ispace-idx) = buffer(idx+1:ispace-1)

                     else if (index('from_input',trim(buffer(1:idx-1))) /= 0) then
                        ispace = idx+1
                        do while ((ispace < eos) .and. (buffer(ispace:ispace) /= ' '))
                           ispace = ispace + 1
                        end do
                        from_input(i) = ' '
                        from_input(i)(1:ispace-idx) = buffer(idx+1:ispace-1)

                     else if (index('z_dim_name',trim(buffer(1:idx-1))) /= 0) then
                        ispace = idx+1
                        do while ((ispace < eos) .and. (buffer(ispace:ispace) /= ' '))
                           ispace = ispace + 1
                        end do
                        z_dim_name(i) = ' '
                        z_dim_name(i)(1:ispace-idx) = buffer(idx+1:ispace-1)

                     else if (index('output_stagger',trim(buffer(1:idx-1))) /= 0) then
                        if (index('M',trim(buffer(idx+1:eos-1))) /= 0) then
                           output_stagger(i) = M
                        else if (index('U',trim(buffer(idx+1:eos-1))) /= 0) then
                           output_stagger(i) = U
                        else if (index('V',trim(buffer(idx+1:eos-1))) /= 0) then
                           output_stagger(i) = V
                        else if (index('HH',trim(buffer(idx+1:eos-1))) /= 0) then
                           output_stagger(i) = HH
                        else if (index('VV',trim(buffer(idx+1:eos-1))) /= 0) then
                           output_stagger(i) = VV
                        end if

                     else if (index('output',trim(buffer(1:idx-1))) /= 0) then
                        if (index('yes',trim(buffer(idx+1:eos-1))) /= 0) then
                           output_this_field(i) = .true.
                        else if (index('no',trim(buffer(idx+1:eos-1))) /= 0) then
                           output_this_field(i) = .false.
                        end if

                     else if (index('is_u_field',trim(buffer(1:idx-1))) /= 0) then
                        if (index('yes',trim(buffer(idx+1:eos-1))) /= 0) then
                           is_u_field(i) = .true.
                        else if (index('no',trim(buffer(idx+1:eos-1))) /= 0) then
                           is_u_field(i) = .false.
                        end if

                     else if (index('is_v_field',trim(buffer(1:idx-1))) /= 0) then
                        if (index('yes',trim(buffer(idx+1:eos-1))) /= 0) then
                           is_v_field(i) = .true.
                        else if (index('no',trim(buffer(idx+1:eos-1))) /= 0) then
                           is_v_field(i) = .false.
                        end if
       
                     else if (index('derived',trim(buffer(1:idx-1))) /= 0) then
                        if (index('yes',trim(buffer(idx+1:eos-1))) /= 0) then
                           is_derived_field(i) = .true.
                        else if (index('no',trim(buffer(idx+1:eos-1))) /= 0) then
                           is_derived_field(i) = .false.
                        end if
       
                     else if (index('interp_option',trim(buffer(1:idx-1))) /= 0) then
                        ispace = idx+1
                        do while ((ispace < eos) .and. (buffer(ispace:ispace) /= ' '))
                           ispace = ispace + 1
                        end do
                        interp_method(i) = ' '
                        interp_method(i)(1:ispace-idx) = buffer(idx+1:ispace-1)

                     else if (index('vertical_interp_option',trim(buffer(1:idx-1))) /= 0) then
                        ispace = idx+1
                        do while ((ispace < eos) .and. (buffer(ispace:ispace) /= ' '))
                           ispace = ispace + 1
                        end do
                        v_interp_method(i) = ' '
                        v_interp_method(i)(1:ispace-idx) = buffer(idx+1:ispace-1)

                     else if (index('interp_mask',trim(buffer(1:idx-1))) /= 0) then
                        ispace = idx+1
                        do while ((ispace < eos) .and. (buffer(ispace:ispace) /= ' '))
                           ispace = ispace + 1
                        end do
                        p1 = index(buffer(idx+1:ispace-1),'(')
                        p2 = index(buffer(idx+1:ispace-1),')')
                        if (p1 == 0 .or. p2 == 0) then
                           call mprintf(.true.,WARN, &
                                        'Problem in specifying interp_mask flag. Setting masked flag to 0.')
                           interp_mask(i) = ' '
                           interp_mask(i)(1:ispace-idx) = buffer(idx+1:ispace-1)
                           interp_mask_val(i) = 0
                        else 
                           interp_mask(i) = ' '
                           interp_mask(i)(1:p1) = buffer(idx+1:idx+p1-1)
                           read(buffer(idx+p1+1:idx+p2-1),*,err=1000) interp_mask_val(i)
                        end if
      
                     else if ((index('masked',trim(buffer(1:idx-1))) /= 0) .and. &
                              (len_trim(buffer(1:idx-1)) == 6)) then
                        if (index('water',trim(buffer(idx+1:eos-1))) /= 0) then
                           masked(i) = 0
                        else if (index('land',trim(buffer(idx+1:eos-1))) /= 0) then
                           masked(i) = 1
                        end if
           
                     else if ((index('flag_in_output',trim(buffer(1:idx-1))) /= 0) .and. &
                              (len_trim(buffer(1:idx-1)) == 14)) then
                        flag_string = ' '
                        flag_string(1:eos-idx-1) = buffer(idx+1:eos-1)
                        if (c_list_search(flag_in_output_list, flag_string, flag_val)) then
                           call mprintf(.true.,WARN, 'In METGRID.TBL, %s is given as a flag more than once.', &
                                        s1=flag_string)
                        else
                           flag_in_output(i)(1:eos-idx-1) = buffer(idx+1:eos-1)
                           write(flag_val,'(i1)') 1
                           call c_list_insert(flag_in_output_list, flag_string, flag_val)
                        end if
           
                     else if (index('fill_missing',trim(buffer(1:idx-1))) /= 0) then
                        read(buffer(idx+1:eos-1),*) fill_missing(i)
   
                     else if (index('missing_value',trim(buffer(1:idx-1))) /= 0) then
                        read(buffer(idx+1:eos-1),*) missing_value(i)
   
                     else if (index('fill_lev',trim(buffer(1:idx-1))) /= 0) then
                        ispace = idx+1
                        do while ((ispace < eos) .and. (buffer(ispace:ispace) /= ' '))
                           ispace = ispace + 1
                        end do
                        fill_string = ' '
                        fill_string(1:ispace-idx-1) = buffer(idx+1:ispace-1)
                        ispace = index(fill_string,':')
                        if (ispace /= 0) then
                           write(lev_string,'(a)') fill_string(1:ispace-1)
                        else
                           write(lev_string,'(a)') 'all'
                        end if
                        write(fill_string,'(a)') trim(fill_string(ispace+1:128))
                        fill_string(128-ispace:128) = ' '
                        if (c_list_search(fill_lev_list(i), lev_string, fill_string)) then
                           call mprintf(.true.,WARN, &
                                        'In entry %i of METGRID.TBL, multiple fields are specified '// &
                                        'to fill level %s. %s will be used.', &
                                        i1=i, s1=trim(lev_string), s2=trim(fill_string))
                        else
                           call c_list_insert(fill_lev_list(i), lev_string, fill_string)
                        end if
       
                     else
                        call mprintf(.true.,WARN, 'In METGRID.TBL, unrecognized option %s in entry %i.', s1=buffer(1:idx-1), i1=idx)
                     end if
          
                  end if   !} index(buffer(1:eos-1),'=') /= 0
          
                  buffer = buffer(eos+1:BUFSIZE)
               end do   ! while eos /= 0 }
        
            end if   !} index(buffer, '=====') /= 0
   
         end if
      end do
   
      close(funit)
   
      return

   1000 call mprintf(.true.,ERROR,'The mask value of the interp_mask specification must '// &
                     'be a real value, enclosed in parentheses immediately after the field name.') 
   
   1001 call mprintf(.true.,ERROR,'Could not open file METGRID.TBL')

   end subroutine read_interp_table


   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   ! Name: get_special_threshold
   !
   ! Pupose:
   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   subroutine get_special_threshold(interp_opt, threshold, istatus)

      implicit none

      ! Arguments
      integer, intent(out) :: istatus
      real, intent(out) :: threshold
      character (len=128), intent(in) :: interp_opt

      ! Local variables
      integer :: i, p1, p2

      istatus = 1
      threshold = 1.0

      i = index(interp_opt,'special')
      if (i /= 0) then

         ! Check for a threshold
         p1 = index(interp_opt(i:128),'(')
         p2 = index(interp_opt(i:128),')')
         if (p1 /= 0 .and. p2 /= 0) then
            read(interp_opt(p1+1:p2-1),*,err=1000) threshold
         else
            call mprintf(.true.,WARN, 'Problem in specifying threshold for special interp option. Setting threshold to 1.0')
            threshold = 1.0
         end if
      end if
      istatus = 0

      return

1000  call mprintf(.true.,ERROR, &
                   'Threshold option to special interpolator must be a real number, '// &
                   'enclosed in parentheses immediately after keyword "special"')

   end subroutine get_special_threshold


   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   ! Name: get_constant_fill_lev
   !
   ! Pupose:
   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   subroutine get_constant_fill_lev(fill_opt, fill_const, istatus)

      implicit none

      ! Arguments
      integer, intent(out) :: istatus
      real, intent(out) :: fill_const
      character (len=128), intent(in) :: fill_opt

      ! Local variables
      integer :: i, p1, p2

      istatus = 1
      fill_const = NAN 

      i = index(fill_opt,'const')
      if (i /= 0) then

         ! Check for a threshold
         p1 = index(fill_opt(i:128),'(')
         p2 = index(fill_opt(i:128),')')
         if (p1 /= 0 .and. p2 /= 0) then
            read(fill_opt(p1+1:p2-1),*,err=1000) fill_const
         else
            call mprintf(.true.,WARN, 'Problem in specifying fill_lev constant. Setting fill_const to %f', f1=NAN)
            fill_const = NAN
         end if
      end if
      istatus = 0

      return

1000  call mprintf(.true.,ERROR, &
                   'Constant option to fill_lev must be a real number, enclosed in parentheses '// &
                   'immediately after keyword "const"')

   end subroutine get_constant_fill_lev


   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   ! Name: get_fill_src_level
   !
   ! Purpose:
   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   subroutine get_fill_src_level(fill_opt, fill_src, fill_src_level)

      implicit none

      ! Arguments
      integer, intent(out) :: fill_src_level
      character (len=128), intent(in) :: fill_opt
      character (len=128), intent(out) :: fill_src

      ! Local variables
      integer :: p1, p2

      ! Check for a level in parentheses
      p1 = index(fill_opt,'(')
      p2 = index(fill_opt,')')
      if (p1 /= 0 .and. p2 /= 0) then
         read(fill_opt(p1+1:p2-1),*,err=1000) fill_src_level
         fill_src = ' '
         write(fill_src,'(a)') fill_opt(1:p1-1)
      else
         fill_src_level = 1 
         fill_src = fill_opt
      end if

      return

1000  call mprintf(.true.,ERROR, &
                   'For fill_lev specification, level in source field must be an integer, '// &
                   'enclosed in parentheses immediately after the fieldname')

   end subroutine get_fill_src_level


   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   ! Name: interp_option_destroy
   !
   ! Purpose:
   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   subroutine interp_option_destroy()

      implicit none

      ! Local variables
      integer :: i

      deallocate(fieldname)
      deallocate(from_input)
      deallocate(z_dim_name)
      deallocate(interp_method)
      deallocate(v_interp_method)
      deallocate(masked)
      deallocate(fill_missing)
      deallocate(missing_value)
      do i=1,num_entries
         call list_destroy(fill_lev_list(i))
      end do 
      deallocate(fill_lev_list)
      deallocate(interp_mask)
      deallocate(interp_mask_val)
      deallocate(flag_in_output)
      deallocate(output_stagger)
      deallocate(output_this_field)
      deallocate(is_u_field)
      deallocate(is_v_field)
      deallocate(is_derived_field)
      call list_destroy(flag_in_output_list)

   end subroutine interp_option_destroy

end module interp_option_module
